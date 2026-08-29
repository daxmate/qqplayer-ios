//
//  LyricsSearchProvider.swift
//  QQPlayer
//
//  多源歌词搜索（网易云 + lrclib），供用户手动挑选歌词。
//  协议与桌面版 QQPlayer 后端 /api/lyric/search 一致：
//  - 网易云：eapi 搜索候选（前 5 个）逐个拉取歌词全文 + 中文翻译
//  - lrclib：/api/search 结果直接携带 syncedLyrics（无翻译）
//  两个源并发搜索，netease 在前、lrclib 在后（桌面版同顺序）。
//

import Foundation

/// 歌词搜索候选（统一两个源的返回结构；text 为 LRC 全文，tlyric 为中文翻译）
struct LyricsSearchCandidate: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        case netease
        case lrclib

        /// 界面显示名
        var displayName: String {
            switch self {
            case .netease: return "网易云"
            case .lrclib: return "lrclib"
            }
        }
    }

    let id: UUID
    let source: Source
    let title: String
    let artist: String
    let duration: Double?
    /// LRC 全文（netease 搜索时已拉取；lrclib 直接带 syncedLyrics）
    let text: String
    /// 中文翻译 LRC（仅网易云）
    let tlyric: String?

    init(
        id: UUID = UUID(),
        source: Source,
        title: String,
        artist: String,
        duration: Double?,
        text: String,
        tlyric: String?
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.artist = artist
        self.duration = duration
        self.text = text
        self.tlyric = tlyric
    }
}

struct LyricsSearchProvider: Sendable {
    static let shared = LyricsSearchProvider()

    private let netease = NeteaseLyricsProvider.shared
    private let lrclibBaseURL = "https://lrclib.net/api"

    /// 双源并发搜索：netease 在前、lrclib 在后；全部失败返回 []
    func search(title: String, artist: String) async -> [LyricsSearchCandidate] {
        let query = "\(title) \(artist)".trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        async let neteaseCandidates = searchNetease(query: query)
        async let lrclibCandidates = searchLRCLib(title: title, artist: artist)
        return await neteaseCandidates + lrclibCandidates
    }

    // MARK: - 网易云

    /// eapi 搜索候选（前 5 个）逐个并发拉取歌词全文 + 中文翻译；结果按搜索相关度排序
    private func searchNetease(query: String) async -> [LyricsSearchCandidate] {
        guard let songs = try? await netease.search(query: query, limit: 8) else {
            return []
        }

        let top = Array(songs.prefix(5))
        // 并发拉歌词；用字典收集后按候选顺序重排（相关度排序稳定，与桌面版一致）
        let fetched = await withTaskGroup(
            of: (index: Int, candidate: LyricsSearchCandidate?)?.self,
            returning: [Int: LyricsSearchCandidate].self
        ) { group in
            for (index, song) in top.enumerated() {
                group.addTask {
                    guard let result = try? await self.netease.getLyric(songID: song.id),
                          !result.lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    return (
                        index,
                        LyricsSearchCandidate(
                            source: .netease,
                            title: song.title,
                            artist: song.artist,
                            duration: song.duration,
                            text: result.lrc,
                            tlyric: result.tlyric
                        )
                    )
                }
            }
            var collected: [Int: LyricsSearchCandidate] = [:]
            for await item in group {
                if let item {
                    collected[item.index] = item.candidate
                }
            }
            return collected
        }

        return top.indices.compactMap { fetched[$0] }
    }

    // MARK: - lrclib

    /// lrclib /api/search：只保留带时间戳的 syncedLyrics（纯文本歌词对播放器无用）
    private func searchLRCLib(title: String, artist: String) async -> [LyricsSearchCandidate] {
        var components = URLComponents(string: "\(lrclibBaseURL)/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(
            "QQPlayer/1.0 (https://github.com/daxmate/qqplayer-ios)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            let hits = try JSONDecoder().decode([LRCLibSearchHit].self, from: data)
            return hits.compactMap { hit -> LyricsSearchCandidate? in
                guard !hit.instrumental,
                      let synced = hit.syncedLyrics,
                      !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return LyricsSearchCandidate(
                    source: .lrclib,
                    title: hit.trackName,
                    artist: hit.artistName,
                    duration: hit.duration,
                    text: synced,
                    tlyric: nil
                )
            }
        } catch {
            print("❌ Failed to search lrclib.net: \(error)")
            return []
        }
    }
}

// MARK: - API 模型

private struct LRCLibSearchHit: Codable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
}
