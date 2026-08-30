//  PlayerEngine+AudioScheduling.swift
//  QQPlayer
//
//  Gapless audio scheduling, preloading, background monitoring, and track-end
//  detection for PlayerEngine.
//
import AVFoundation
import Foundation
import UIKit

extension PlayerEngine {
    // MARK: - Audio Scheduling Helper

    @discardableResult
    func scheduleSegment(from startFrame: AVAudioFramePosition, file: AVAudioFile, track: Track? = nil, trackIndex: Int? = nil) -> Bool {
        // Safety check: Ensure audio engine is running
        guard audioEngine.isRunning else {
            print("❌ Cannot schedule segment: audio engine is not running")
            return false
        }

        // Validate startFrame is within bounds
        guard startFrame >= 0 && startFrame < file.length else {
            print("❌ Invalid startFrame: \(startFrame), file length: \(file.length)")
            return false
        }

        let remaining = file.length - startFrame
        guard remaining > 0 else {
            print("❌ No remaining frames to schedule: startFrame=\(startFrame), length=\(file.length)")
            return false
        }

        // Validate that frameCount doesn't overflow AVAudioFrameCount
        guard remaining <= AVAudioFrameCount.max else {
            print("❌ Remaining frames exceed AVAudioFrameCount.max: \(remaining)")
            return false
        }

        let scheduledGeneration = scheduleGeneration
        let scheduledTrackId = track?.stableId
        let scheduledIndex = trackIndex

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                await self?.handleScheduledSegmentFinished(
                    generation: scheduledGeneration,
                    trackStableId: scheduledTrackId,
                    trackIndex: scheduledIndex
                )
            }
        }

        print("✅ Successfully scheduled segment: startFrame=\(startFrame), frameCount=\(remaining)")

        // Start background monitoring when we schedule a segment
        startBackgroundMonitoring()
        return true
    }

    private func nextPlayableIndexForPreload() -> Int? {
        guard !playbackQueue.isEmpty, !isLoopingSong else { return nil }
        if currentIndex < playbackQueue.count - 1 {
            return currentIndex + 1
        }
        if isRepeating {
            return 0
        }
        return nil
    }

    private func canGaplesslySchedule(_ currentFile: AVAudioFile, with nextFile: AVAudioFile) -> Bool {
        let currentFormat = currentFile.processingFormat
        let nextFormat = nextFile.processingFormat
        return abs(currentFormat.sampleRate - nextFormat.sampleRate) < 0.1
            && currentFormat.channelCount == nextFormat.channelCount
            && currentFormat.commonFormat == nextFormat.commonFormat
            && currentFormat.isInterleaved == nextFormat.isInterleaved
    }

    func preloadAndScheduleNextIfNeeded() {
        guard !usingSFBEngine,
              isPlaying,
              audioFile != nil,
              let nextIndex = nextPlayableIndexForPreload(),
              playbackQueue.indices.contains(nextIndex) else {
            return
        }

        let candidate = playbackQueue[nextIndex]

        if nextTrack?.stableId == candidate.stableId {
            scheduleGaplessNextIfPossible()
            return
        }

        clearPreloadedNext()

        let preloadGeneration = loadGeneration
        isPreloadingNext = true
        preloadNextTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let url = URL(fileURLWithPath: candidate.path)

            guard !SFBAudioEngineManager.canHandle(url: url) else {
                self.isPreloadingNext = false
                return
            }

            // Avoid holding security-scoped resources for a future track.
            guard await LibraryIndexer.shared.resolveBookmarkForTrack(candidate) == nil else {
                self.isPreloadingNext = false
                return
            }

            do {
                try await self.cloudDownloadManager.ensureLocal(url)
                try Task.checkCancellation()

                let file = try await self.openNativeAudioFile(at: url, qos: .utility)
                try Task.checkCancellation()

                guard self.loadGeneration == preloadGeneration,
                      self.playbackQueue.indices.contains(nextIndex),
                      self.playbackQueue[nextIndex].stableId == candidate.stableId else {
                    return
                }

                self.nextAudioFile = file
                self.nextTrack = candidate
                self.nextTrackIndex = nextIndex
                self.isPreloadingNext = false
                self.scheduleGaplessNextIfPossible()
            } catch is CancellationError {
                self.isPreloadingNext = false
            } catch {
                self.isPreloadingNext = false
                print("⚠️ Failed to preload next track for gapless playback: \(error)")
            }
        }
    }

    private func scheduleGaplessNextIfPossible() {
        guard !gaplessScheduled,
              !usingSFBEngine,
              isPlaying,
              audioEngine.isRunning,
              let currentFile = audioFile,
              let nextFile = nextAudioFile,
              let nextTrack,
              let nextTrackIndex else {
            return
        }

        guard canGaplesslySchedule(currentFile, with: nextFile) else {
            print("ℹ️ Next track format differs; using normal transition instead of gapless")
            return
        }

        let currentStartFrame = AVAudioFramePosition(seekTimeOffset * currentFile.processingFormat.sampleRate)
        let remainingFrames = max(0, currentFile.length - currentStartFrame)
        guard remainingFrames > 0 else { return }

        let scheduled = scheduleSegment(from: 0, file: nextFile, track: nextTrack, trackIndex: nextTrackIndex)
        guard scheduled else { return }

        nextTimelineStartSampleTime = nodeTimelineStartSampleTime + remainingFrames
        gaplessScheduled = true
        print("✅ Gapless next track scheduled: \(nextTrack.title)")
    }

    private func promoteGaplessNextIfAvailable() -> Bool {
        guard gaplessScheduled,
              let nextFile = nextAudioFile,
              let next = nextTrack,
              let nextIndex = nextTrackIndex,
              playbackQueue.indices.contains(nextIndex) else {
            return false
        }

        currentIndex = nextIndex
        // Play history: settle the finished track before switching.
        PlayHistoryRecorder.shared.playbackEnded(track: currentTrack, at: playbackTime)
        currentTrack = next
        audioFile = nextFile
        duration = Double(nextFile.length) / nextFile.processingFormat.sampleRate
        seekTimeOffset = 0
        nodeTimelineStartSampleTime = nextTimelineStartSampleTime ?? currentNodeSampleTime() ?? 0
        playbackTime = currentTimeForCurrentNativeFile()
        playbackState = .playing
        isPlaying = true
        // Play history: the gapless next track starts a new session.
        PlayHistoryRecorder.shared.playbackBegan(track: next, at: 0)

        nextAudioFile = nil
        nextTrack = nil
        nextTrackIndex = nil
        nextTimelineStartSampleTime = nil
        gaplessScheduled = false
        isPreloadingNext = false

        resetNowPlayingCachesForTrackChange()
        lastControlCenterUpdate = 0
        updateNowPlayingInfoEnhanced()
        updateWidgetData()
        preloadAndScheduleNextIfNeeded()
        return true
    }

    func currentNodeSampleTime() -> AVAudioFramePosition? {
        // playerTime(forNodeTime:) raises an ObjC exception - not nil - when
        // the node is detached or the engine is torn down mid-query (App Store
        // crash group spanning 1.0.6-1.2.2), so check attachment and engine
        // state before asking.
        guard audioEngine.attachedNodes.contains(playerNode),
              audioEngine.isRunning,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return playerTime.sampleTime
    }

    func currentTimeForCurrentNativeFile() -> TimeInterval {
        guard let audioFile = audioFile,
              let currentSampleTime = currentNodeSampleTime() else {
            // 中断诊断（2026-08-29）：此处是可疑 fallback——引擎已停/节点无效时退回
            // 冻结的 playbackTime（后台 UI timer 不跑，锁屏早于播放开始则其值为 0）
            let fallbackDiag = "🔍 [intr] currentTime fallback to playbackTime=\(playbackTime)s "
                + "(audioFile=\(audioFile != nil) sampleTime=nil engineRunning=\(audioEngine.isRunning))"
            print(fallbackDiag)
            InterruptionDiagnostics.log(fallbackDiag)
            return playbackTime
        }

        let relativeSampleTime = max(0, currentSampleTime - nodeTimelineStartSampleTime)
        let time = seekTimeOffset + Double(relativeSampleTime) / audioFile.processingFormat.sampleRate
        return min(max(time, 0), duration)
    }

    private func handleScheduledSegmentFinished(generation: UInt64, trackStableId: String?, trackIndex: Int?) async {
        guard generation == scheduleGeneration,
              isPlaying,
              !usingSFBEngine else {
            return
        }

        if let trackStableId, trackStableId != currentTrack?.stableId {
            return
        }

        if promoteGaplessNextIfAvailable() {
            return
        }

        await handleTrackEnd()
    }

    func startBackgroundMonitoring() {
        // Only create a background task if we don't already have one
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                print("🚨 Background task expiring during playback")
                Task { @MainActor in
                    self?.endBackgroundMonitoring()
                }
            }
        }

        // Start a timer that works in background
        backgroundCheckTimer?.invalidate()
        backgroundCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkIfTrackEnded()
            }
        }
    }

    func endBackgroundMonitoring() {
        backgroundCheckTimer?.invalidate()
        backgroundCheckTimer = nil

        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func stopSilentPlaybackForPause() {
        pausedSilentPlayer?.stop()
        pausedSilentPlayer = nil
        print("🔇 Stopped silent playback for pause")
    }

    // NOTE: maintainAudioSessionForBackground() used to live here. It force-
    // reactivated the audio session while paused "to prevent termination" -
    // the same keep-alive anti-pattern as the silent player, and its only
    // caller was that player's error path. Being suspended while paused is the
    // correct outcome, so it has been removed rather than left to be re-wired.

    private func checkIfTrackEnded() async {
        // Check if audio has finished playing
        guard isPlaying else { return }

        // Skip native player checks when using SFBAudioEngine
        guard !usingSFBEngine else { return }

        // Check if player node has stopped naturally (reached end).
        // A stopped *engine* (config change, interruption) also makes the node
        // report not-playing - only treat it as track end while the engine runs.
        if audioEngine.isRunning && !playerNode.isPlaying && audioFile != nil {
            // Track has ended
            if promoteGaplessNextIfAvailable() {
                return
            }
            await handleTrackEnd()
            return
        }

        // Alternative check: position-based
        if audioFile != nil {
            let currentTime = currentTimeForCurrentNativeFile()

            if currentTime >= duration - 0.2 && duration > 0 {
                guard !gaplessScheduled else { return }
                // Track is ending
                isPlaying = false // Prevent multiple triggers
                await handleTrackEnd()
            }
        }
    }

    func handleTrackEnd() async {
        guard !isLoadingTrack else { return }

        if promoteGaplessNextIfAvailable() {
            return
        }

        if isLoopingSong, let t = currentTrack {
            let loaded = await loadTrack(t)
            if loaded { play() }
            return
        }

        if currentIndex < playbackQueue.count - 1 {
            currentIndex = (currentIndex + 1) % playbackQueue.count
            let next = playbackQueue[currentIndex]
            let loaded = await loadTrack(next, preservePlaybackTime: false)
            if loaded {
                if usingSFBEngine && isPlaying {
                    playbackState = .playing
                    startPlaybackTimer()
                } else {
                    play()
                }
            }
            return
        }

        if isRepeating, !playbackQueue.isEmpty {
            currentIndex = 0
            currentTrack = playbackQueue[0]
            let loaded = await loadTrack(playbackQueue[0])
            if loaded {
                if usingSFBEngine && isPlaying {
                    playbackState = .playing
                    startPlaybackTimer()
                } else {
                    play()
                }
            }
            return
        }

        stop()
    }
}
