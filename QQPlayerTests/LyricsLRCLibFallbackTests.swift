//
//  LyricsLRCLibFallbackTests.swift
//  QQPlayerTests
//
//  lrclib 中文歌「拉丁歌手名」fallback 测试：
//  背景：lrclib 收录的中文歌 artist 多为拉丁拼写（「孙燕姿」→ Stefanie Sun），
//  带中文 artist 搜索（/api/search?track_name=..&artist_name=孙燕姿）返回 0 条，
//  只有按 track_name 搜才命中（如「我怀念的」→ Stefanie Sun 版，duration 289s）。
//  - 自动获取（LyricsManager.searchForSyncedLyrics）：带 artist 0 条 → 只按歌名重搜，
//    按 duration ±2s 命中带时间轴的歌词
//  - 搜索页（LyricsSearchProvider.searchLRCLib）：带 artist 简繁双查 0 条 → 只按歌名（简/繁）重搜
//
//  隔离说明：本测试**不自建 MockURLProtocol**（那个是其他 API 测试套件共用的进程级
//  静态 handler，跨 suite 并行会互相覆盖），而是用本文件底部自带的
//  LRCLibMockURLProtocol —— 独立 URLProtocol 类，静态状态只属于自己，
//  与其他 suite 完全隔离，suite 无需 .serialized。
//

import Foundation
import Testing

@testable import QQPlayer

@Suite
struct LyricsLRCLibFallbackTests {
    /// 真实 lrclib 响应结构（字段与 /api/search 返回一致）
    private static let stefanieHitJSON = """
    [{
        "id": 35092461,
        "name": "我怀念的",
        "trackName": "我怀念的",
        "artistName": "Stefanie Sun",
        "albumName": "逆光",
        "duration": 289.0,
        "instrumental": false,
        "plainLyrics": "我怀念的是无言感动",
        "syncedLyrics": "[00:17.07]我问为什么\n[00:18.60]那女孩传简讯给我"
    }]
    """

    init() {
        LRCLibMockURLProtocol.reset()
    }

    /// handler：lrclib 请求带 artist_name → 0 条（模拟中文 artist 匹配不上拉丁拼写）；
    /// 不带 artist_name → 命中 Stefanie Sun 版；其他 host 抛错（网易云等路径不测）。
    private func makeHandler() -> LRCLibMockURLProtocol.Handler {
        { request in
            guard let url = request.url, url.host == "lrclib.net" else {
                throw URLError(.unsupportedURL)
            }
            let hasArtist = url.query?.contains("artist_name=") ?? false
            return LRCLibMockURLProtocol.jsonResponse(
                hasArtist ? "[]" : Self.stefanieHitJSON,
                for: request
            )
        }
    }

    // MARK: - 自动获取

    @Test("自动获取：中文 artist 0 条时按歌名兜底重搜，duration 命中 Stefanie Sun 版")
    func autoFetchFallback() async {
        LRCLibMockURLProtocol.handler = makeHandler()
        LyricsManager.lyricsURLSession = LRCLibMockURLProtocol.makeSession()
        defer { LyricsManager.lyricsURLSession = .shared }

        let lyrics = await LyricsManager.shared.searchForSyncedLyrics(
            trackName: "我怀念的",
            artistName: "孙燕姿",
            duration: 289
        )

        #expect(lyrics != nil)
        #expect(lyrics?.source == .lrclib)
        #expect(lyrics?.syncedLyrics.isEmpty == false)

        // 恰好两次 /api/search：先带 artist（0 条）→ 兜底只按歌名
        let searchRequests = LRCLibMockURLProtocol.receivedRequests.filter {
            $0.url?.path.contains("/search") ?? false
        }
        #expect(searchRequests.count == 2)
        #expect(searchRequests[0].url?.query?.contains("artist_name=") == true)
        #expect(searchRequests[1].url?.query?.contains("artist_name=") == false)
    }

    @Test("自动获取：带 artist 直接命中时不触发兜底（英文歌等正常路径）")
    func autoFetchNoFallbackWhenHit() async {
        let hitJSON = """
        [{
            "id": 1,
            "name": "Flower Sea",
            "trackName": "Flower Sea",
            "artistName": "Jay Chou",
            "albumName": "Album",
            "duration": 270.0,
            "instrumental": false,
            "plainLyrics": "",
            "syncedLyrics": "[00:01.00]Flower Sea"
        }]
        """
        LRCLibMockURLProtocol.handler = { request in
            guard let url = request.url, url.host == "lrclib.net" else {
                throw URLError(.unsupportedURL)
            }
            return LRCLibMockURLProtocol.jsonResponse(hitJSON, for: request)
        }
        LyricsManager.lyricsURLSession = LRCLibMockURLProtocol.makeSession()
        defer { LyricsManager.lyricsURLSession = .shared }

        let lyrics = await LyricsManager.shared.searchForSyncedLyrics(
            trackName: "Flower Sea",
            artistName: "Jay Chou",
            duration: 270
        )

        #expect(lyrics != nil)
        #expect(lyrics?.source == .lrclib)
        // 命中即返回，只发一次请求（不触发兜底重搜）
        let searchRequests = LRCLibMockURLProtocol.receivedRequests.filter {
            $0.url?.path.contains("/search") ?? false
        }
        #expect(searchRequests.count == 1)
    }

    // MARK: - 搜索页

    @Test("搜索页：中文 artist 简繁双查 0 条时按歌名兜底，lrclib 候选出现 Stefanie Sun")
    func searchPageFallback() async {
        LRCLibMockURLProtocol.handler = makeHandler()

        var provider = LyricsSearchProvider()
        provider.urlSession = LRCLibMockURLProtocol.makeSession()

        let results = await provider.searchLRCLib(title: "我怀念的", artist: "孙燕姿")

        #expect(results.contains { $0.source == .lrclib && $0.artist == "Stefanie Sun" })
        #expect(results.first?.text.contains("我问为什么") == true)

        // 兜底阶段发过不带 artist_name 的请求
        let fallbackRequests = LRCLibMockURLProtocol.receivedRequests.filter {
            ($0.url?.query?.contains("artist_name=") ?? true) == false
        }
        #expect(fallbackRequests.isEmpty == false)
    }
}

// MARK: - 本测试专用 URLProtocol（与其他 suite 隔离）

/// 独立 URLProtocol 子类：handler/请求记录是**本类自己**的静态状态，
/// 与其他 suite 共用的 MockURLProtocol 互不干扰——即使跨 suite 并行执行，
/// 本测试的 lrclib 请求也只走本类的 handler。
private final class LRCLibMockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    /// 预设响应处理器：测试按请求 URL 返回对应响应；抛错视为网络失败。
    nonisolated(unsafe) static var handler: Handler?

    /// 本测试收到的全部请求（按发起顺序）。
    nonisolated(unsafe) static var receivedRequests: [URLRequest] = []

    /// 每个测试开始前调用，清空上一个测试的残留状态。
    static func reset() {
        handler = nil
        receivedRequests = []
    }

    /// 构造注入本协议的 URLSession（ephemeral，不共享缓存）。
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LRCLibMockURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// 便捷方法：构造 JSON 响应。
    static func jsonResponse(
        _ body: String, status: Int = 200, for request: URLRequest
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    // MARK: - URLProtocol

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        LRCLibMockURLProtocol.receivedRequests.append(request)

        guard let handler = LRCLibMockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
