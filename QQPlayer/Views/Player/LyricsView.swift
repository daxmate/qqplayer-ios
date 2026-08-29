//
//  LyricsView.swift
//  QQPlayer
//
//  Lyrics display with synchronized scrolling
//

import SwiftUI

struct LyricsView: View {
    let lyrics: Lyrics?
    let currentTime: TimeInterval
    let isLoading: Bool
    let onClose: () -> Void
    @State private var scrollTarget: Int?
    @State private var settings = DeleteSettings.load()
    @State private var dragX: CGFloat = 0

    var body: some View {
        ZStack {
            // 不透明底色：不透出下层播放页封面（否则歌词字被图片干扰）
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            // 媒体库同款背景光晕（跟随设置主题色变化）
            ScreenSpecificBackgroundView(screen: .library)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if let lyrics = lyrics {
                    if lyrics.isInstrumental {
                        instrumentalView
                    } else if !lyrics.syncedLyrics.isEmpty {
                        syncedLyricsView(lyrics.syncedLyrics)
                    } else if !lyrics.plainLyrics.isEmpty {
                        plainLyricsView(lyrics.plainLyrics)
                    } else {
                        noLyricsView
                    }
                } else {
                    noLyricsView
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BackgroundColorChanged"))) { _ in
            settings = DeleteSettings.load()
        }
        // 右滑关闭：跟手位移，达阈值/快速回甩滑出（Apple Music 风格）
        .offset(x: dragX)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard value.translation.width > 0 else { return }
                    dragX = value.translation.width
                }
                .onEnded { value in
                    if PlayerDismissGesture.shouldDismissLyrics(
                        translation: value.translation.width,
                        predictedTranslation: value.predictedEndTranslation.width
                    ) {
                        // 由外层 transition（move trailing）负责滑出动画，从当前位置滑出
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragX = 0
                        }
                    }
                }
        )
    }

    // MARK: - Synced Lyrics

    private func syncedLyricsView(_ lines: [LyricsLine]) -> some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Reduced spacer at top - use more space
                            Spacer()
                                .frame(height: geometry.size.height / 2 - 40)

                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                let isActive = isLineActive(line, at: index, in: lines)
                                let distance = distanceFromActive(index: index, lines: lines)

                                lyricLineView(
                                    line: line,
                                    isActive: isActive,
                                    distance: distance,
                                    index: index
                                )
                            }

                            // Reduced spacer at bottom - use more space
                            Spacer()
                                .frame(height: geometry.size.height / 2 - 40)
                        }
                    }
                    .disabled(true)  // Disable user scrolling - auto-scroll only

                    // Fade gradients at top and bottom（贴近系统底色，歌词边缘柔和融入背景）
                    VStack(spacing: 0) {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(uiColor: .systemBackground).opacity(0.95),
                                Color(uiColor: .systemBackground).opacity(0.7),
                                Color(uiColor: .systemBackground).opacity(0.3),
                                Color.clear,
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 150)

                        Spacer()

                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color(uiColor: .systemBackground).opacity(0.3),
                                Color(uiColor: .systemBackground).opacity(0.7),
                                Color(uiColor: .systemBackground).opacity(0.95),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 150)
                    }
                    .allowsHitTesting(false)
                }
                .onChange(of: currentTime) { _, _ in
                    updateActiveLineAndScroll(for: lines, in: proxy)
                }
                .onAppear {
                    updateActiveLineAndScroll(for: lines, in: proxy)
                }
            }
        }
    }

    private func distanceFromActive(index: Int, lines: [LyricsLine]) -> Int {
        for (i, line) in lines.enumerated() where isLineActive(line, at: i, in: lines) {
            return abs(index - i)
        }
        return 99
    }

    private func lyricLineView(line: LyricsLine, isActive: Bool, distance: Int, index: Int) -> some View {
        VStack(spacing: 4) {
            Text(line.text)
                .font(fontForLine(isActive: isActive, distance: distance))
                .fontWeight(isActive ? .bold : .semibold)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(lineColor(distance: distance, isActive: isActive))
                .multilineTextAlignment(.center)
                .shadow(
                    color: isActive ? settings.backgroundColorChoice.color.opacity(0.5) : .clear,
                    radius: isActive ? 20 : 0,
                    x: 0,
                    y: 0
                )

            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: translationFontSize(isActive: isActive, distance: distance), weight: .regular))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(translationColor(distance: distance, isActive: isActive))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, isActive ? 24 : 16)
        .id(index)
        .scaleEffect(isActive ? 1.02 : (distance <= 1 ? 0.97 : 0.94), anchor: .center)
        .opacity(lineOpacity(distance: distance, isActive: isActive))
        .animation(
            .interpolatingSpring(
                mass: 0.5,
                stiffness: 200,
                damping: 20,
                initialVelocity: 0
            ),
            value: isActive
        )
    }

    private func translationFontSize(isActive: Bool, distance: Int) -> CGFloat {
        if isActive {
            return 16
        } else if distance <= 1 {
            return 14
        } else {
            return 13
        }
    }

    private func translationColor(distance: Int, isActive: Bool) -> Color {
        if isActive {
            return settings.backgroundColorChoice.color.opacity(0.95)
        } else if distance <= 1 {
            return .secondary.opacity(0.85)
        } else if distance <= 2 {
            return .secondary.opacity(0.5)
        } else {
            return .secondary.opacity(0.25)
        }
    }

    private func fontForLine(isActive: Bool, distance: Int) -> Font {
        if isActive {
            return .system(size: 26, weight: .bold)
        } else if distance <= 1 {
            return .system(size: 19, weight: .semibold)
        } else {
            return .system(size: 16, weight: .medium)
        }
    }

    private func lineColor(distance: Int, isActive: Bool) -> Color {
        if isActive {
            // 当前句用设置中的主题色
            return settings.backgroundColorChoice.color
        } else if distance <= 1 {
            return .primary.opacity(0.75)
        } else if distance <= 2 {
            return .primary.opacity(0.4)
        } else {
            return .primary.opacity(0.18)
        }
    }

    private func lineOpacity(distance: Int, isActive: Bool) -> Double {
        if isActive {
            return 1.0
        } else if distance <= 1 {
            return 0.9
        } else if distance <= 2 {
            return 0.6
        } else if distance <= 3 {
            return 0.3
        } else {
            return 0.15  // Show distant lines dimly instead of hiding
        }
    }

    // MARK: - Plain Lyrics

    private func plainLyricsView(_ text: String) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Top padding
                Spacer()
                    .frame(height: 24)

                Text(text)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineSpacing(10)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)

                // Bottom padding
                Spacer()
                    .frame(height: 40)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - States

    private var instrumentalView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Animated icon with glass background
                ZStack {
                    // Large outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.4),
                                    settings.backgroundColorChoice.color.opacity(0.2),
                                    settings.backgroundColorChoice.color.opacity(0.05),
                                    Color.clear,
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 30)

                    // Glass circle
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            settings.backgroundColorChoice.color.opacity(0.6),
                                            settings.backgroundColorChoice.color.opacity(0.3),
                                            settings.backgroundColorChoice.color.opacity(0.1),
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(
                            color: settings.backgroundColorChoice.color.opacity(0.3),
                            radius: 25,
                            x: 0,
                            y: 10
                        )

                    Image(systemName: "music.note")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(.primary)
                        .shadow(color: settings.backgroundColorChoice.color.opacity(0.6), radius: 15)
                }

                VStack(spacing: 12) {
                    Text("Instrumental")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("This track has no lyrics")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(44)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.3),
                                    Color.primary.opacity(0.15),
                                    settings.backgroundColorChoice.color.opacity(0.2),
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )

                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.05),
                                    Color.clear,
                                    settings.backgroundColorChoice.color.opacity(0.08),
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: settings.backgroundColorChoice.color.opacity(0.2), radius: 35, x: 0, y: 15)
            )
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var noLyricsView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Animated icon with glass background
                ZStack {
                    // Large outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.4),
                                    settings.backgroundColorChoice.color.opacity(0.2),
                                    settings.backgroundColorChoice.color.opacity(0.05),
                                    Color.clear,
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 30)

                    // Glass circle
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            settings.backgroundColorChoice.color.opacity(0.6),
                                            settings.backgroundColorChoice.color.opacity(0.3),
                                            settings.backgroundColorChoice.color.opacity(0.1),
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(
                            color: settings.backgroundColorChoice.color.opacity(0.3),
                            radius: 25,
                            x: 0,
                            y: 10
                        )

                    Image(systemName: "text.badge.xmark")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(.primary)
                        .shadow(color: settings.backgroundColorChoice.color.opacity(0.6), radius: 15)
                }

                VStack(spacing: 12) {
                    Text("No Lyrics Available")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Lyrics not found for this track")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(44)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.3),
                                    Color.primary.opacity(0.15),
                                    settings.backgroundColorChoice.color.opacity(0.2),
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )

                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.05),
                                    Color.clear,
                                    settings.backgroundColorChoice.color.opacity(0.08),
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: settings.backgroundColorChoice.color.opacity(0.2), radius: 35, x: 0, y: 15)
            )
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Animated loading with glass background
                ZStack {
                    // Large outer glow - animated
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.4),
                                    settings.backgroundColorChoice.color.opacity(0.2),
                                    settings.backgroundColorChoice.color.opacity(0.05),
                                    Color.clear,
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 30)

                    // Glass circle
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            settings.backgroundColorChoice.color.opacity(0.6),
                                            settings.backgroundColorChoice.color.opacity(0.3),
                                            settings.backgroundColorChoice.color.opacity(0.1),
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(
                            color: settings.backgroundColorChoice.color.opacity(0.3),
                            radius: 25,
                            x: 0,
                            y: 10
                        )

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                        .scaleEffect(1.5)
                }

                VStack(spacing: 12) {
                    Text("Loading Lyrics")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Fetching from metadata and online sources")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(44)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.3),
                                    Color.primary.opacity(0.15),
                                    settings.backgroundColorChoice.color.opacity(0.2),
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )

                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    settings.backgroundColorChoice.color.opacity(0.05),
                                    Color.clear,
                                    settings.backgroundColorChoice.color.opacity(0.08),
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: settings.backgroundColorChoice.color.opacity(0.2), radius: 35, x: 0, y: 15)
            )
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Helper Methods

    private func isLineActive(_ line: LyricsLine, at index: Int, in lines: [LyricsLine]) -> Bool {
        LyricTiming.activeLineIndex(time: currentTime, in: lines) == index
    }

    private func updateActiveLineAndScroll(for lines: [LyricsLine], in proxy: ScrollViewProxy) {
        for (index, line) in lines.enumerated() where isLineActive(line, at: index, in: lines) {
            withAnimation(
                .interpolatingSpring(
                    mass: 1.0,
                    stiffness: 170,
                    damping: 25,
                    initialVelocity: 0
                )
            ) {
                proxy.scrollTo(index, anchor: .center)
            }
            break
        }
    }
}

// MARK: - Preview

#Preview {
    LyricsView(
        lyrics: Lyrics(
            plainLyrics: "Sample lyrics\nLine 2\nLine 3",
            syncedLyrics: [
                LyricsLine(timestamp: 0, text: "Sample lyrics"),
                LyricsLine(timestamp: 5, text: "Line 2"),
                LyricsLine(timestamp: 10, text: "Line 3"),
            ],
            isInstrumental: false,
            source: .embedded
        ),
        currentTime: 6.0,
        isLoading: false,
        onClose: {}
    )
}
