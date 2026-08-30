//
//  MacPlayerView.swift
//  QQPlayer
//
//  macOS player detail page: artwork, track info, playback controls, and a
//  draggable progress bar. QQPlayerMac target only.
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 300, height: 300)
                    .shadow(radius: 8, y: 4)

                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 300, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 72))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 300, height: 300)

            // Track info
            VStack(spacing: 6) {
                Text(track?.title ?? "未在播放")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(artistName ?? "")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Progress bar
            VStack(spacing: 6) {
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
            .frame(maxWidth: 460)

            // Controls
            HStack(spacing: 28) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .disabled(track == nil)
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                .buttonStyle(.plain)
                .disabled(track == nil)
                .keyboardShortcut(.space)

                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .disabled(track == nil)
                .keyboardShortcut(.rightArrow, modifiers: [.command])
            }

            Spacer()
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: track?.stableId) {
            guard let track else {
                artwork = nil
                artworkTrackId = nil
                return
            }
            let art = await ArtworkManager.shared.getArtwork(for: track)
            artwork = art
            artworkTrackId = track.stableId
        }
    }
}
