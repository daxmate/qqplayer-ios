import SwiftUI

/// 播放页折叠控制容器：常驻进度条 + 三键（上一首/播放暂停/下一首），
/// 上滑展开更多按钮（播放顺序 + 队列/定时/歌词/隔空播放），下滑收起。
struct CollapsiblePlayerControls: View {
    @ObservedObject private var playerEngine = PlayerEngine.shared
    @State private var isExpanded = false

    let duration: TimeInterval
    let accentColor: Color
    let onSeek: (TimeInterval) -> Void
    let showSleepTimerButton: Bool
    let showLyricsButton: Bool
    let isLoadingLyrics: Bool
    let sleepTimerEndDate: Date?
    let onStartSleepTimer: (Int) -> Void
    let onCancelSleepTimer: () -> Void
    let onShowQueue: () -> Void
    let onShowLyrics: () -> Void
    let onShowAirPlay: () -> Void

    var body: some View {
        VStack(spacing: UIScreen.main.scale < UIScreen.main.nativeScale ? 12 : 16) {
            PlayerProgressSection(
                duration: duration,
                accentColor: accentColor,
                onSeek: onSeek
            )

            threeButtonRow

            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(.caption2)
                .foregroundColor(.secondary)

            if isExpanded {
                expandedSection
            }
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height < -30, !isExpanded {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isExpanded = true
                        }
                    } else if value.translation.height > 30, isExpanded {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isExpanded = false
                        }
                    }
                }
        )
    }

    // MARK: - 常驻三键行

    private var threeButtonRow: some View {
        HStack(spacing: min(35, UIScreen.main.bounds.width * 0.08)) {
            previousButton
            playPauseButton
            nextButton
        }
        .padding(.horizontal, min(21, UIScreen.main.bounds.width * 0.055))
        .padding(.vertical, 21)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 25))
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var previousButton: some View {
        Button(action: {
            Task {
                await playerEngine.previousTrack()
            }
        }) {
            Image(systemName: "backward.fill")
                .font(UIScreen.main.scale < UIScreen.main.nativeScale ? .title2 : .title)
        }
    }

    private var playPauseButton: some View {
        Button(action: {
            if playerEngine.isPlaying {
                playerEngine.pause()
            } else {
                playerEngine.play()
            }
        }) {
            Image(systemName: playerEngine.isPlaying ? "pause.fill" : "play.fill")
                .font(UIScreen.main.scale < UIScreen.main.nativeScale ? .title : .largeTitle)
        }
    }

    private var nextButton: some View {
        Button(action: {
            Task {
                await playerEngine.nextTrack()
            }
        }) {
            Image(systemName: "forward.fill")
                .font(UIScreen.main.scale < UIScreen.main.nativeScale ? .title2 : .title)
        }
    }

    // MARK: - 展开区

    private var expandedSection: some View {
        VStack(spacing: 12) {
            playOrderButton
            additionalRow
        }
        .padding(.top, 2)
    }

    // 播放顺序四态轮换按钮：顺序播放 → 随机播放 → 循环列表 → 单曲循环
    private var playOrderButton: some View {
        Button(action: {
            playerEngine.cyclePlaybackOrderMode()
        }) {
            HStack(spacing: 8) {
                Image(systemName: playOrderIcon)
                    .font(.title3)
                Text(playOrderTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isPlayOrderActive ? accentColor : .primary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .accessibilityLabel(playOrderTitle)
    }

    private var playOrderMode: PlaybackOrderMode {
        playerEngine.playbackOrderMode
    }

    private var playOrderIcon: String {
        switch playOrderMode {
        case .sequential: return "arrow.clockwise"
        case .shuffle: return "shuffle"
        case .repeatAll: return "repeat"
        case .repeatOne: return "repeat.1"
        }
    }

    private var playOrderTitle: String {
        switch playOrderMode {
        case .sequential: return Localized.playOrderSequential
        case .shuffle: return Localized.playOrderShuffle
        case .repeatAll: return Localized.playOrderRepeatAll
        case .repeatOne: return Localized.playOrderRepeatOne
        }
    }

    private var isPlayOrderActive: Bool {
        switch playOrderMode {
        case .sequential: return false
        case .shuffle, .repeatAll, .repeatOne: return true
        }
    }

    // 附加行：队列 / 定时 / 歌词 / 隔空播放（逻辑从 PlayerView 整体搬入）
    private var additionalRow: some View {
        // Both optional controls can be shown at once. The two settings toggles
        // are independent, but this row used to have a single shared middle
        // slot in which the sleep timer took priority - enabling it silently
        // hid the lyrics button. Each button fills the row evenly, so the
        // layout absorbs two, three or four of them.
        HStack(spacing: 12) {
            queueButton
            if showSleepTimerButton {
                sleepTimerButton
            }
            if showLyricsButton {
                lyricsButton
            }
            airPlayButton
        }
        .padding(.horizontal, 5)
    }

    private var queueButton: some View {
        Button(action: {
            onShowQueue()
        }) {
            Image(systemName: "list.bullet")
                .font(UIScreen.main.scale < UIScreen.main.nativeScale ? .title2 : .title)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var airPlayButton: some View {
        Button(action: {
            onShowAirPlay()
        }) {
            Image(systemName: "airplayaudio")
                .font(UIScreen.main.scale < UIScreen.main.nativeScale ? .title2 : .title)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: 25)
                .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var lyricsButton: some View {
        Button(action: {
            onShowLyrics()
        }) {
            ZStack {
                Image(systemName: "quote.bubble")
                    .font(UIScreen.main.scale < UIScreen.main.nativeScale ? .title2 : .title)
                    .foregroundColor(.primary)

                if isLoadingLyrics {
                    ProgressView()
                        .scaleEffect(0.7)
                        .offset(x: 15, y: -10)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var sleepTimerButton: some View {
        Menu {
            Button(Localized.sleepTimer15Minutes) {
                onStartSleepTimer(15)
            }
            Button(Localized.sleepTimer30Minutes) {
                onStartSleepTimer(30)
            }
            Button(Localized.sleepTimer45Minutes) {
                onStartSleepTimer(45)
            }
            Button(Localized.sleepTimer60Minutes) {
                onStartSleepTimer(60)
            }

            if sleepTimerEndDate != nil {
                Divider()

                Button(Localized.cancelSleepTimer, role: .destructive) {
                    onCancelSleepTimer()
                }
            }
        } label: {
            Image(systemName: sleepTimerEndDate == nil ? "timer" : "timer.circle.fill")
                .font(UIScreen.main.scale < UIScreen.main.nativeScale ? .title2 : .title)
                .foregroundColor(sleepTimerEndDate == nil ? .primary : accentColor)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.vertical, 16)
        }
        .menuOrder(.fixed)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Localized.sleepTimer)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
