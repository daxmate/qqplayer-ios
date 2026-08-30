//  SFBAudioEngineManager.swift
//  QQPlayer
//
//  Manages SFBAudioEngine playback for Opus, Vorbis, and DSD formats
//
//  Split into domain extensions (behavior-identical refactor):
//    SFBAudioEngineManager+Playback.swift  playback control/seek/rate/time
//    SFBAudioEngineManager+Queue.swift     progress/format compatibility
//
import AudioToolbox
import AVFoundation
import CarPlay
import Foundation
import SFBAudioEngine
import UIKit

private struct AVAudioUnitEQBox: @unchecked Sendable {
    let node: AVAudioUnitEQ
}

@MainActor
class SFBAudioEngineManager: NSObject, ObservableObject, AudioPlayer.Delegate {
    static let shared = SFBAudioEngineManager()

    var audioPlayer: AudioPlayer?
    var currentTrack: SFBTrack?
    var updateTimer: Timer?
    private var eqAttachmentFailed = false

    // Gapless playback support
    var nextTrackURL: URL?
    var onTrackNearingEnd: (() -> Void)?
    private var hasTriggeredNearEnd = false

    nonisolated private func configureDefaultSFBBands(for equalizer: AVAudioUnitEQ) {
        let numberOfBands = equalizer.bands.count
        let minFreq = 20.0
        let maxFreq = 20000.0

        for i in 0 ..< numberOfBands {
            let band = equalizer.bands[i]
            let frequency = minFreq * pow(maxFreq / minFreq, Double(i) / Double(numberOfBands - 1))
            band.frequency = Float(frequency)
            band.gain = 0.0
            band.bandwidth = 1.0
            band.filterType = .parametric
            band.bypass = false
        }
    }

    func cleanupEqualizer() {
        if let equalizer = sfbEqualizer {
            audioPlayer?.modifyProcessingGraph { [weak self] engine in
                guard let self else { return }
                if engine.attachedNodes.contains(equalizer) {
                    self.removeEqualizer(equalizer, from: engine)
                }
            }
        }
        sfbEqualizer = nil
    }

    nonisolated private func removeEqualizer(_ equalizer: AVAudioUnitEQ, from engine: AVAudioEngine) {
        guard engine.attachedNodes.contains(equalizer) else {
            print("ℹ️ EQ node already detached")
            return
        }

        let mixerConnection = engine.inputConnectionPoint(for: engine.mainMixerNode, inputBus: 0)
        let isEQFeedingMixer = mixerConnection?.node === equalizer

        let upstreamConnection = engine.inputConnectionPoint(for: equalizer, inputBus: 0)
        let upstreamNode = upstreamConnection?.node

        if isEQFeedingMixer, let upstreamNode {
            let upstreamBus = upstreamConnection?.bus ?? 0
            let reconnectFormat = upstreamNode.outputFormat(forBus: upstreamBus)

            engine.disconnectNodeInput(engine.mainMixerNode)
            engine.disconnectNodeOutput(equalizer)
            engine.disconnectNodeInput(equalizer)
            engine.detach(equalizer)

            engine.connect(upstreamNode, to: engine.mainMixerNode, format: reconnectFormat)
            print("🔗 Restored \(upstreamNode) → mainMixerNode after EQ removal")
        } else {
            engine.disconnectNodeOutput(equalizer)
            engine.disconnectNodeInput(equalizer)
            engine.detach(equalizer)
            print("🧹 Removed SFBAudioEngine EQ (no upstream reconnection needed)")
        }
    }

    func attachEqualizerToEngine(with format: AVAudioFormat?, retryCount: Int = 0) {
        guard let player = audioPlayer else { return }

        // Skip EQ if not enabled by user
        guard eqManager.isEnabled else {
            print("ℹ️ EQ not enabled by user - skipping attachment")
            return
        }

        // Skip EQ if previous attachment failed (prevents repeated crashes)
        if eqAttachmentFailed {
            print("⚠️ EQ attachment previously failed - skipping to prevent crash")
            return
        }

        let maxRetries = 3
        let eqEnabled = eqManager.isEnabled
        let globalGain = Float(eqManager.globalGain)

        guard formatSupportsSFBEQ(format) else {
            print("⚠️ SFBAudioEngine EQ not supported for format: \(format?.description ?? "nil")")
            player.modifyProcessingGraph { [weak self] engine in
                guard let self else { return }
                if let existing = engine.attachedNodes.compactMap({ $0 as? AVAudioUnitEQ }).first {
                    self.removeEqualizer(existing, from: engine)
                }
            }
            Task { @MainActor [weak self] in self?.sfbEqualizer = nil }
            return
        }

        // 闭包在 AVAudioEngine 内部串行队列执行，不能直接读 MainActor 隔离的
        // sfbEqualizer（数据竞争，Swift 6 编译期不检查，2026-08-29 审计 #8）：
        // 在 MainActor 侧预拷贝为 @unchecked Sendable 的 box，闭包内只用 box。
        let existingEqualizerBox = sfbEqualizer.map { AVAudioUnitEQBox(node: $0) }
        player.modifyProcessingGraph { [weak self] engine in
            guard let self else { return }

            var equalizer = existingEqualizerBox?.node

            if equalizer == nil {
                equalizer = engine.attachedNodes.compactMap { $0 as? AVAudioUnitEQ }.first
            }

            if equalizer == nil {
                let newEQ = AVAudioUnitEQ(numberOfBands: 16)
                newEQ.globalGain = globalGain
                newEQ.bypass = !eqEnabled
                self.configureDefaultSFBBands(for: newEQ)
                engine.attach(newEQ)
                equalizer = newEQ
                print("✅ EQ node attached via modifyProcessingGraph")
            } else if let eq = equalizer, !engine.attachedNodes.contains(where: { $0 === eq }) {
                engine.attach(eq)
                print("✅ Reattached existing SFBAudioEngine EQ node")
            }

            guard let equalizer else { return }

            let eqBox = AVAudioUnitEQBox(node: equalizer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sfbEqualizer = eqBox.node
                self.applySFBEQSettings()
            }

            let eqConnectedToMain = engine.outputConnectionPoints(for: equalizer, outputBus: 0)
                .contains(where: { $0.node === engine.mainMixerNode })

            if eqConnectedToMain {
                print("🎛️ SFBAudioEngine EQ already present in graph")
                return
            }

            if let connection = engine.inputConnectionPoint(for: engine.mainMixerNode, inputBus: 0),
               let upstreamNode = connection.node,
               upstreamNode !== equalizer {
                let bus = connection.bus
                // Prefer the node's actual render format - the decoder format can
                // differ from what the player node outputs, and a mismatched
                // connect throws
                let nodeFormat = upstreamNode.outputFormat(forBus: bus)
                let connectFormat = nodeFormat.sampleRate > 0 ? nodeFormat : format
                engine.disconnectNodeInput(engine.mainMixerNode)

                // Try to connect - if it fails, mark EQ as failed
                do {
                    try ObjCExceptionCatcher.tryCatch({
                        engine.connect(equalizer, to: engine.mainMixerNode, format: connectFormat)
                        engine.connect(upstreamNode, to: equalizer, format: connectFormat)
                    })
                } catch {
                    print("❌ EQ connection failed in attachEqualizerToEngine: \(error.localizedDescription)")
                    // CRITICAL: the mixer input was already disconnected above.
                    // Restore the original connection or ALL SFB playback
                    // (Opus/Vorbis/DSD) stays silent (issue #75).
                    try? ObjCExceptionCatcher.tryCatch({
                        engine.disconnectNodeOutput(equalizer)
                        engine.connect(upstreamNode, to: engine.mainMixerNode, format: nodeFormat.sampleRate > 0 ? nodeFormat : nil)
                    })
                    print("🔗 Restored direct connection after EQ failure")
                    Task { @MainActor [weak self] in
                        self?.eqAttachmentFailed = true
                    }
                    return
                }

                print("🔗 Inserted EQ between \(upstreamNode) and mainMixerNode")
                return
            }

            let fallbackNode = engine.attachedNodes.first(where: { node in
                if node === equalizer || node === engine.mainMixerNode || node === engine.outputNode { return false }
                let className = String(describing: type(of: node))
                return className.contains("SFBAudioPlayerNode") || node is AVAudioPlayerNode
            })

            if let sourceNode = fallbackNode {
                let nodeFormat = sourceNode.outputFormat(forBus: 0)
                let connectFormat = nodeFormat.sampleRate > 0 ? nodeFormat : format
                engine.disconnectNodeInput(engine.mainMixerNode)
                engine.disconnectNodeOutput(sourceNode)

                // Try to connect - if it fails, mark EQ as failed
                do {
                    try ObjCExceptionCatcher.tryCatch({
                        engine.connect(sourceNode, to: equalizer, format: connectFormat)
                        engine.connect(equalizer, to: engine.mainMixerNode, format: connectFormat)
                    })
                } catch {
                    print("❌ EQ connection failed (fallback): \(error.localizedDescription)")
                    // CRITICAL: restore the direct connection or SFB playback
                    // stays silent (issue #75)
                    try? ObjCExceptionCatcher.tryCatch({
                        engine.disconnectNodeOutput(equalizer)
                        engine.connect(sourceNode, to: engine.mainMixerNode, format: nodeFormat.sampleRate > 0 ? nodeFormat : nil)
                    })
                    print("🔗 Restored direct connection after EQ failure (fallback)")
                    Task { @MainActor [weak self] in
                        self?.eqAttachmentFailed = true
                    }
                    return
                }

                print("🔗 Inserted EQ between \(sourceNode) and mainMixerNode (fallback)")
                return
            }

            print("⚠️ Unable to locate upstream node for SFBAudioEngine EQ insertion")

            if retryCount < maxRetries {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard let self else { return }
                    self.attachEqualizerToEngine(with: format, retryCount: retryCount + 1)
                }
            }
        }
    }

    // Store decoder properties for seeking when AudioFile properties are unavailable
    var decoderFrameLength: Int64 = 0
    var decoderSampleRate: Double = 0

    // EQ integration for SFBAudioEngine (native approach following wiki)
    let eqManager = EQManager.shared
    var sfbEqualizer: AVAudioUnitEQ?
    // Track last sample rate to avoid unnecessary changes
    var lastConfiguredSampleRate: Double = 0

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    // CarPlay environment detection
    @Published var isCarPlayEnvironment = false

    private override init() {
        super.init()
        isCarPlayEnvironment = Self.detectCarPlay()
        print("🔄 SFBAudioEngine Manager initialized - CarPlay: \(isCarPlayEnvironment)")
    }

    /// Detects if the app is running in a CarPlay environment
    private static func detectCarPlay() -> Bool {
        // Check if a CarPlay template scene is connected. The scene exists
        // before AVAudioSession necessarily exposes a `.carAudio` route.
        if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if scene is CPTemplateApplicationScene
                    || scene.session.role == .carTemplateApplication {
                    print("🚗 CarPlay scene detected: \(scene)")
                    return true
                }
            }
        }

        // Additional check: CarPlay audio routes
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        print("🎧 Current audio route: \(currentRoute.outputs.map { "\($0.portName) (\($0.portType))" }.joined(separator: ", "))")

        for output in currentRoute.outputs where output.portType == .carAudio {
            print("🚗 CarPlay audio route detected: \(output.portName)")
            return true
        }

        return false
    }

    /// Re-check CarPlay status (call when audio route changes)
    func updateCarPlayStatus() {
        let wasCarPlay = isCarPlayEnvironment
        isCarPlayEnvironment = Self.detectCarPlay()

        if wasCarPlay != isCarPlayEnvironment {
            if isCarPlayEnvironment {
                print("🚗 Switched to CarPlay - stopping SFBAudioEngine")
                stop()
                audioPlayer = nil
            } else {
                print("📱 Switched from CarPlay - SFBAudioEngine available again")
            }
        }
    }

    func setupAudioPlayer() {
        guard audioPlayer == nil else { return }

        // Don't initialize SFBAudioEngine in CarPlay environment
        if isCarPlayEnvironment {
            print("🚗 Skipping SFBAudioEngine setup - running in CarPlay")
            return
        }

        // Try to create AudioPlayer
        audioPlayer = AudioPlayer()

        // Verify player was created successfully
        guard audioPlayer != nil else {
            print("⚠️ SFBAudioEngine AudioPlayer creation returned nil")
            return
        }

        audioPlayer?.delegate = self
        print("🔄 SFBAudioEngine AudioPlayer initialized successfully")
    }

    func resetAudioPlayer() {
        audioPlayer?.stop()
        cleanupEqualizer()
        audioPlayer = nil
        audioPlayer = AudioPlayer()
        audioPlayer?.delegate = self
        print("🔄 SFBAudioEngine AudioPlayer reset")
    }

    nonisolated private func formatSupportsSFBEQ(_ format: AVAudioFormat?) -> Bool {
        guard let format else { return true }
        let streamDescription = format.streamDescription.pointee
        let isLinearPCM = streamDescription.mFormatID == kAudioFormatLinearPCM
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        return isLinearPCM && isFloat && streamDescription.mBitsPerChannel == 32
    }

    // MARK: - AudioPlayer.Delegate

    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, reconfigureProcessingGraph engine: AVAudioEngine, with format: AVAudioFormat) -> AVAudioNode {
        print("🔄 SFBAudioEngine processing graph reconfiguration for format: \(format)")
        print("🔍 Engine state - isRunning: \(engine.isRunning), attachedNodes: \(engine.attachedNodes.count)")

        // We can't access MainActor properties from nonisolated context
        // So we always skip EQ in this delegate method and rely on attachEqualizerToEngine instead
        // This prevents crashes and keeps the delegate method simple
        print("ℹ️ Skipping EQ in delegate - EQ will be attached via attachEqualizerToEngine if enabled")
        return engine.mainMixerNode
    }

    // MARK: - Background/Foreground Optimization

    func optimizeForBackground() async {
        print("🔒 Optimizing SFBAudioEngine for background/lock screen")

        // Increase buffer size significantly for background stability
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setPreferredIOBufferDuration(0.100) // 100ms buffer for lock screen
            print("✅ Increased buffer to 100ms for lock screen stability")
        } catch {
            print("⚠️ Failed to increase buffer for background: \(error)")
        }

        // Reduce processing load by temporarily disabling EQ if possible
        if let equalizer = sfbEqualizer {
            equalizer.bypass = true
            print("✅ Temporarily bypassed EQ for background stability")
        }
    }

    func optimizeForForeground() async {
        print("🔓 Restoring SFBAudioEngine for foreground")

        // Restore normal buffer size
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setPreferredIOBufferDuration(0.040) // Back to 40ms
            print("✅ Restored buffer to 40ms for foreground")
        } catch {
            print("⚠️ Failed to restore buffer for foreground: \(error)")
        }

        // Re-enable EQ based on current settings
        if let equalizer = sfbEqualizer {
            equalizer.bypass = !eqManager.isEnabled
            print("✅ Restored EQ bypass state for foreground")
        }
    }
}
