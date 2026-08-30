//
//  MacPlayerView.swift
//  QQPlayer
//
//  macOS player detail page: artwork, track info, playback controls, a
//  draggable progress bar, and a lyrics panel with karaoke controls.
//  QQPlayerMac target only.
//

import SwiftUI

struct MacPlayerView: View {
    let track: Track?
    let artistName: String?
    let isPlaying: Bool
    let duration: TimeInterval
    let playbackTime: TimeInterval
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var artwork: ArtworkImage?
    @State private var artworkTrackId: String?
    @State private var dragTime: TimeInterval?
    @State private var isDragging = false
    @State private var lyrics: Lyrics?
    @State private var lyricsLoading = false
    @State private var showLyrics = true
    @ObservedObject private var karaoke = KaraokeController.shared

    var body: some View {
        VStack(spacing: 0) {
            playerSection
            if showLyrics {
                Divider()
                MacLyricsView(
                    lyrics: lyrics,
                    currentTime: playbackTime,
                    isLoading: lyricsLoading,
                    onClose: { showLyrics = false }
                )
                .frame(height: 330)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: track?.stableId) {
            guard let track else {
                artwork = nil
                artworkTrackId = nil
                lyrics = nil
                return
            }
            let art = await ArtworkManager.shared.getArtwork(for: track)
            artwork = art
            artworkTrackId = track.stableId

            // 歌词：优先缓存/本地，在线搜索失败不阻塞 UI（跟 iOS 语义一致）
            lyricsLoading = true
            lyrics = await LyricsManager.shared.getLyrics(for: track)
            lyricsLoading = false
        }
    }

    // MARK: - Player section

    private var playerSection: some View {
        VStack(spacing: 16) {
            Spacer()

            // Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 240, height: 240)
                    .shadow(radius: 8, y: 4)

                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 240, height: 240)

            // Track info
            VStack(spacing: 4) {
                Text(track?.title ?? "未在播放")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(artistName ?? "")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Progress bar
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isDragging ? (dragTime ?? playbackTime) : playbackTime },
                        set: { dragTime = $0 }
                    ),
                    in: 0 ... max(duration, 0.01),
                    onEditingChanged: { editing in
                        isDragging = editing
                        if !editing, let dragTime {
                            onSeek(dragTime)
                            self.dragTime = nil
                        }
                    }
                )
                .disabled(track == nil || duration <= 0)

                HStack {
                    Text(MacTimeFormat.format(isDragging ? (dragTime ?? playbackTime) : playbackTime))
                    Spacer()
                    Text(MacTimeFormat.format(duration))
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
            }
            .frame(maxWidth: 420)

            // Controls
            HStack(spacing: 24) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .disabled(track == nil)
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)
                .disabled(track == nil)
                .keyboardShortcut(.space)

                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .disabled(track == nil)
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Divider().frame(height: 24)

                // 跟唱模式开关（双击歌词行的 iOS 语义在 Mac 上没有，给显式按钮）
                Button {
                    karaoke.toggleKaraokeMode()
                } label: {
                    Image(systemName: karaoke.isKaraokeOn ? "mic.fill" : "mic")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundColor(karaoke.isKaraokeOn ? .accentColor : .secondary)
                .disabled(track == nil)
                .help("跟唱模式（倍速 / 单句循环 / AB 循环）")

                // 歌词面板开关
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLyrics.toggle()
                    }
                } label: {
                    Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundColor(showLyrics ? .accentColor : .secondary)
                .help("显示 / 隐藏歌词")
            }

            Spacer()
        }
        .padding(.top, 24)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
