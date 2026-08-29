//
//  LyricsSearchView.swift
//  QQPlayer
//
//  歌词搜索页：小歌词窗口右滑从左侧滑入。
//  双源搜索（网易云 + lrclib）候选列表，用户手动挑选；选中后持久化为该歌曲的手动指定歌词。
//  背景与全屏歌词页一致（不透明系统底色 + 媒体库同款光晕），交互参考桌面版 LyricSpecModal。
//

import SwiftUI

struct LyricsSearchView: View {
    let track: Track
    let accentColor: Color
    let onClose: () -> Void
    /// 应用搜索结果（选中候选）或恢复自动（nil）；由外层负责刷新歌词显示
    let onApply: (Lyrics?) -> Void

    @State private var searchTitle: String
    @State private var searchArtist: String
    @State private var searching = false
    @State private var searched = false
    @State private var searchError = ""
    @State private var results: [LyricsSearchCandidate] = []
    @State private var applyingIndex: Int?
    @State private var manualActive = false
    @State private var dragX: CGFloat = 0

    init(
        track: Track,
        accentColor: Color,
        onClose: @escaping () -> Void,
        onApply: @escaping (Lyrics?) -> Void
    ) {
        self.track = track
        self.accentColor = accentColor
        self.onClose = onClose
        self.onApply = onApply
        _searchTitle = State(initialValue: track.title)
        // 预填歌手名（与播放页 artistButton 同款查库逻辑）
        let artistName: String = {
            guard let artistId = track.artistId,
                  let artist = try? DatabaseManager.shared.read({ db in
                      try Artist.fetchOne(db, key: artistId)
                  }) else {
                return ""
            }
            return artist.name
        }()
        _searchArtist = State(initialValue: artistName)
    }

    var body: some View {
        ZStack {
            // 不透明底色：不透出下层播放页封面（歌词页同款做法）
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            // 媒体库同款背景光晕（跟随设置主题色变化）
            ScreenSpecificBackgroundView(screen: .library)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if manualActive {
                    manualStatusRow
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                if !searchError.isEmpty {
                    Text(searchError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }

                content
                    .padding(.top, 12)
            }
        }
        .onAppear {
            Task {
                manualActive = await LyricsManager.shared.hasManualLyrics(for: track)
            }
            // 进入页面自动搜索当前歌曲（预填关键词），用户可改词再搜
            doSearch()
        }
        // 左滑关闭：跟手位移，达阈值/快速回甩滑出（与全屏歌词页右滑关闭同款，方向镜像）
        .offset(x: dragX)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard value.translation.width < 0 else { return }
                    dragX = value.translation.width
                }
                .onEnded { value in
                    if PlayerDismissGesture.shouldDismissLyricsSearch(
                        translation: value.translation.width,
                        predictedTranslation: value.predictedEndTranslation.width
                    ) {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragX = 0
                        }
                    }
                }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("关闭歌词搜索")

            VStack(alignment: .leading, spacing: 2) {
                Text("歌词搜索")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(track.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if searching {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("歌名", text: $searchTitle)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.search)
                    .onSubmit { doSearch() }

                TextField("歌手（可选）", text: $searchArtist)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.search)
                    .onSubmit { doSearch() }

                Button(action: doSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(searching)
                .opacity(searching ? 0.5 : 1)
                .accessibilityLabel("搜索")
            }
        }
    }

    // MARK: - Manual Status

    private var manualStatusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(accentColor)

            Text("已手动指定歌词")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                Task {
                    await LyricsManager.shared.clearManualLyrics(for: track)
                    manualActive = false
                    onApply(nil) // 恢复自动：外层重新加载
                }
            } label: {
                Text("恢复自动")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if searching && results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("搜索中…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else if searched && results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "text.badge.xmark")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("未找到歌词，试试修改歌名/歌手")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            resultList
        }
    }

    private var resultList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, candidate in
                    resultRow(candidate, at: index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func resultRow(_ candidate: LyricsSearchCandidate, at index: Int) -> some View {
        Button {
            apply(candidate, at: index)
        } label: {
            HStack(spacing: 12) {
                // 来源标签
                Text(candidate.source.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(sourceColor(candidate.source), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !candidate.artist.isEmpty {
                        Text(candidate.artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if candidate.tlyric != nil {
                    Text("译")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(accentColor.opacity(0.6), lineWidth: 1)
                        )
                        .accessibilityLabel("含中文翻译")
                }

                if applyingIndex == index {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(applyingIndex != nil)
        .opacity(applyingIndex != nil && applyingIndex != index ? 0.6 : 1)
    }

    private func sourceColor(_ source: LyricsSearchCandidate.Source) -> Color {
        switch source {
        case .netease: return Color(red: 0.76, green: 0.05, blue: 0.05) // 网易云品牌红
        case .lrclib: return .blue
        }
    }

    // MARK: - Actions

    private func doSearch() {
        let title = searchTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            searchError = "请输入歌名"
            return
        }
        guard !searching else { return }

        searchError = ""
        searched = false
        results = []
        searching = true
        let artist = searchArtist.trimmingCharacters(in: .whitespaces)

        Task {
            let candidates = await LyricsSearchProvider.shared.search(title: title, artist: artist)
            await MainActor.run {
                results = candidates
                searched = true
                searching = false
            }
        }
    }

    private func apply(_ candidate: LyricsSearchCandidate, at index: Int) {
        guard applyingIndex == nil else { return }
        applyingIndex = index
        searchError = ""

        Task {
            let lyrics = await LyricsManager.shared.apply(candidate: candidate, for: track)
            await MainActor.run {
                applyingIndex = nil
                if let lyrics {
                    manualActive = true
                    onApply(lyrics)
                } else {
                    searchError = "应用失败，请重试"
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LyricsSearchView(
        track: Track(
            stableId: "preview",
            title: "花海",
            path: "/tmp/preview.flac"
        ),
        accentColor: .red,
        onClose: {},
        onApply: { _ in }
    )
}
