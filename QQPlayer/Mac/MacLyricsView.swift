//
//  MacLyricsView.swift
//  QQPlayer
//
//  macOS lyrics panel: synchronized scrolling, karaoke mode with
//  speed / single-line loop / AB loop controls (KaraokeControlBar).
//  QQPlayerMac target only — kept out of the iOS target via pbxproj
//  membership exceptions.
//

import SwiftUI

struct MacLyricsView: View {
    let lyrics: Lyrics?
    let currentTime: TimeInterval
    let isLoading: Bool
    let onClose: () -> Void

    @ObservedObject private var karaoke = KaraokeController.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.30), Color.black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("歌词", systemImage: "quote.bubble")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("关闭歌词面板")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView("歌词加载中…")
                Spacer()
            }
        } else if let lyrics {
            if lyrics.isInstrumental {
                emptyState("纯音乐，无歌词")
            } else if !lyrics.syncedLyrics.isEmpty {
                syncedView(lyrics.syncedLyrics)
            } else if !lyrics.plainLyrics.isEmpty {
                plainView(lyrics.plainLyrics)
            } else {
                emptyState("暂无歌词")
            }
        } else {
            emptyState("暂无歌词")
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Synced lyrics

    private func syncedView(_ lines: [LyricsLine]) -> some View {
        let activeIndex = LyricTiming.activeLineIndex(time: currentTime, in: lines)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        VStack(spacing: 2) {
                            Text(line.text)
                                .font(.system(size: 15))
                                .foregroundColor(index == activeIndex ? .white : .secondary)
                                .fontWeight(index == activeIndex ? .semibold : .regular)
                                .multilineTextAlignment(.center)
                                .id(index)
                            if let translation = line.translation, !translation.isEmpty {
                                Text(translation)
                                    .font(.system(size: 12))
                                    .foregroundColor(index == activeIndex ? .white.opacity(0.85) : Color.secondary.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let ts = line.timestamp {
                                Task { await PlayerEngine.shared.seek(to: ts) }
                            }
                            if karaoke.isKaraokeOn {
                                karaoke.clickLine(index: index)
                            }
                        }
                        .scaleEffect(index == activeIndex ? 1.06 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: activeIndex)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 24)
            }
            .onChange(of: activeIndex) { newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                if let activeIndex {
                    proxy.scrollTo(activeIndex, anchor: .center)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if karaoke.isKaraokeOn {
                KaraokeControlBar(accentColor: .accentColor)
                    .padding(.bottom, 10)
                    .background(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    // MARK: - Plain lyrics

    private func plainView(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }
}
