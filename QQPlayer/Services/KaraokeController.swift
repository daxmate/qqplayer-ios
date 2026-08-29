//
//  KaraokeController.swift
//  QQPlayer
//
//  跟唱模式控制器：状态 + 句末决策（纯逻辑可单测）+ 与 PlayerEngine 的薄桥。
//
//  语义对齐桌面版（qqplayer 前端 useAbLoop.ts）：
//  - 双击歌词（小歌词窗/全屏歌词页）进入/退出跟唱模式
//  - 跟唱模式默认「句末自动停」：每句播完停回本句句首（方便反复跟读）
//  - 单句循环：句末自动重播本句
//  - AB 循环：长按 AB 按钮（当前句=A，等待点歌词设 B）→ A~B 区间循环
//  - 倍速：仅慢速档 [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]（学唱歌场景，只慢不快）
//
//  契约（勿改 public API，任务包 A 填实现 / B 消费 UI）：
//  - PlayerEngine 每 0.25s 播放 tick 调 handlePlaybackTick(time:duration:)
//  - UI 歌词加载完成后调 setLyrics(_:)
//  - 切歌时 PlayerEngine 调 resetForNewTrack()
//

import Foundation

/// AB 循环区间状态（a/b 为歌词行号；b == nil 表示等选终点）
struct ABLoopState: Equatable {
    var a: Int
    var b: Int?
}

/// 播放器执行动作（KaraokeController → PlayerEngine 的薄桥；测试注入 fake）
@MainActor
protocol KaraokeActions {
    /// 跳转到某句句首并保持播放状态（seek 保持播放态）
    func seekAndPlay(to time: TimeInterval) async
    /// 跳转到某句句首并暂停（句末自动停）
    func seekAndPause(to time: TimeInterval) async
    /// 应用倍速到音频链（AVAudioUnitTimePitch.rate）
    func setRate(_ rate: Double)
}

/// 跟唱模式控制器（@MainActor 单例，Swift 6 严格并发）
@MainActor
final class KaraokeController: ObservableObject {
    static let shared = KaraokeController()

    // MARK: - 状态（UI 观察）

    @Published private(set) var isKaraokeOn = false
    @Published private(set) var speed: Double = 1.0
    @Published private(set) var isSingleLineLoop = false
    @Published private(set) var abLoop: ABLoopState?

    /// 倍速档位（只慢不快；1.0 在末尾，从 1.0 点一下回到 0.5 从慢开始练）
    static let speedLevels: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

    /// 当前歌词行（UI 歌词加载完成后注入；句末决策依赖）
    private(set) var currentLines: [LyricsLine] = []

    /// 播放器桥（运行时由 PlayerEngine 提供；测试注入 fake）
    var actions: KaraokeActions?

    /// 跳转静默窗口：jumpTo 后 0.3s 内不做句末检测（seek 异步 + tick 读到旧时间
    /// 会误判「旧句句末」重复触发——桌面版 karaokeJumpQuiet 同款，2026-08-23 教训）
    private var jumpQuietUntil: Date = .distantPast

    private init() {
        actions = PlayerEngineKaraokeActions()
    }

    // MARK: - 模式开关（双击歌词 toggle）

    /// 双击：进入/退出跟唱模式；退出时清理 AB/单句循环并恢复 1.0 倍速
    func toggleKaraokeMode() {
        setKaraokeOn(!isKaraokeOn)
    }

    func setKaraokeOn(_ on: Bool) {
        if isKaraokeOn == on { return }
        isKaraokeOn = on
        if on {
            applySpeedToEngine()
        } else {
            // 退出跟唱：清理 AB/单句（避免回到正常播放后句子循环/残留 AB 标注），速度恢复 1.0
            abLoop = nil
            isSingleLineLoop = false
            speed = 1.0
            applySpeedToEngine()
        }
    }

    /// 切歌：AB 行号失效 → 清 AB；保留跟唱模式/速度/单句循环（换歌继续练）
    func resetForNewTrack() {
        abLoop = nil
    }

    /// 歌词行注入（UI 歌词加载/切歌完成后调用）
    func setLyrics(_ lines: [LyricsLine]) {
        currentLines = lines
    }

    // MARK: - 倍速

    /// 循环切换档位（0.5 → 0.6 → … → 1.0 → 0.5）
    func cycleSpeed() {
        let i = Self.speedLevels.firstIndex(of: speed) ?? 0
        speed = Self.speedLevels[(i + 1) % Self.speedLevels.count]
        applySpeedToEngine()
    }

    /// 把当前 speed 应用到播放引擎
    func applySpeedToEngine() {
        actions?.setRate(speed)
    }

    // MARK: - 单句循环 / AB 循环

    func toggleSingleLineLoop() {
        isSingleLineLoop.toggle()
    }

    /// 长按 AB 按钮：当前句 = A，等待点击歌词设 B（b == nil）
    func enterABLoop(currentLine: Int) {
        guard isKaraokeOn,
              currentLine >= 0, currentLine < currentLines.count,
              currentLines[currentLine].timestamp != nil else { return }
        abLoop = ABLoopState(a: currentLine, b: nil)
    }

    /// 单击 AB 按钮（已启用时）：退出 AB 循环
    func exitABLoop() {
        abLoop = nil
    }

    /// 歌词点击统一入口（对齐桌面 clickLine）：
    /// 无 AB → 播放该句；等选终点 → 点击设为 B；区间内 → 跳到该句播放；
    /// 区间外 → 退出 AB 并播放该句
    func clickLine(index: Int) {
        guard isKaraokeOn, currentLines.indices.contains(index) else { return }
        if let ab = abLoop {
            if let b = ab.b {
                if index < ab.a || index > b {
                    exitABLoop()
                    jumpTo(line: index, play: true)
                    return
                }
                jumpTo(line: index, play: true)
                return
            }
            setABEnd(index)
            return
        }
        jumpTo(line: index, play: true)
    }

    /// 等选终点：点击句设为 B（终点在起点前自动交换；点起点本身忽略）
    private func setABEnd(_ lineIndex: Int) {
        guard var ab = abLoop, ab.b == nil,
              currentLines.indices.contains(lineIndex) else { return }
        if lineIndex == ab.a { return }
        var a = ab.a
        var b = lineIndex
        if b < a { swap(&a, &b) }
        ab.a = a
        ab.b = b
        abLoop = ab
    }

    // MARK: - 句末决策（PlayerEngine 播放 tick 每 0.25s 调用）

    /// 播放 tick：跟唱模式下检测句末并执行 句末自动停 / 单句循环 / AB 循环
    func handlePlaybackTick(time: TimeInterval, duration: TimeInterval) {
        guard isKaraokeOn, !currentLines.isEmpty else { return }
        guard Date() > jumpQuietUntil else { return }
        guard let line = LyricTiming.activeLineIndex(time: time, in: currentLines) else { return }
        let end = lineEndTime(line: line, duration: duration)
        guard time >= end else { return }
        handleLineEnd(line)
    }

    /// 本句结束时间 = 下一句句首时间戳；最后一句 = 歌曲时长
    private func lineEndTime(line: Int, duration: TimeInterval) -> TimeInterval {
        if line + 1 < currentLines.count, let next = currentLines[line + 1].timestamp {
            return next
        }
        return duration
    }

    /// 句末处理（对齐桌面 handleKaraokeTick）：
    /// AB 激活 → 按 AB 规则；否则单句循环 → 重播本句；否则句末自动停 → 回句首暂停
    private func handleLineEnd(_ line: Int) {
        if let ab = abLoop {
            if ab.b == nil {
                // 等选终点：任何句播完都跳回 A 循环（桌面同款）
                jumpTo(line: ab.a, play: true)
                return
            }
            if let b = ab.b {
                if line < b {
                    // 区间中间句：自然推进（不干预）
                    return
                }
                if line == b {
                    // B 终点播完 → 跳回 A 重播
                    jumpTo(line: ab.a, play: true)
                    return
                }
            }
            // line > b（seek 跳出区间）：落到单句/自动停
        }
        if isSingleLineLoop {
            jumpTo(line: line, play: true)
        } else {
            jumpTo(line: line, play: false)
        }
    }

    // MARK: - 跳转

    /// 跳转到某句句首；play=false 时跳完暂停（句末自动停）
    private func jumpTo(line: Int, play: Bool) {
        guard currentLines.indices.contains(line),
              let ts = currentLines[line].timestamp else { return }
        jumpQuietUntil = Date().addingTimeInterval(0.3)
        let target = ts
        Task { @MainActor in
            if play {
                await actions?.seekAndPlay(to: target)
            } else {
                await actions?.seekAndPause(to: target)
            }
        }
    }
}

/// PlayerEngine 桥（KaraokeController 默认 actions）
/// setRate 依赖 PlayerEngine.setPlaybackRate（任务包 A 实现：AVAudioUnitTimePitch 接入）
private struct PlayerEngineKaraokeActions: KaraokeActions {
    func seekAndPlay(to time: TimeInterval) async {
        await PlayerEngine.shared.seek(to: time)
    }

    func seekAndPause(to time: TimeInterval) async {
        await PlayerEngine.shared.seek(to: time)
        PlayerEngine.shared.pause()
    }

    func setRate(_ rate: Double) {
        PlayerEngine.shared.setPlaybackRate(rate)
    }
}
