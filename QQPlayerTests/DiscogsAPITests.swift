//
//  DiscogsAPITests.swift
//  QQPlayerTests
//
//  Discogs API 单元测试（MusicAPITests 拆分）：
//  - 搜索+详情、未配置 key 短路、错误路径、findBestMatch、缓存命中/过期清理
//  - MockURLProtocol 拦截全部请求，无真实网络
//
//  本文件是 @Suite(.serialized) struct MusicAPITests 的 extension（骨架与共享基建在
//  MusicAPIMockSupport.swift）：MockURLProtocol 的 handler / 请求记录是进程级静态状态，
//  拆成多个独立套件会跨套件并行执行互相覆盖。
//

import Foundation
import Testing

@testable import QQPlayer

extension MusicAPITests {
    // MARK: - Fixtures：Discogs（本文件专用）

    private static func installDiscogsHandler(
        searchStatus: Int = 200,
        searchBody: String? = nil,
        detailsStatus: Int = 200,
        detailsBody: String? = nil
    ) {
        let search = searchBody ?? Self.discogsSearchJSON(results: [])
        let details = detailsBody ?? Self.discogsArtistJSON(name: "Radiohead", id: 1)
        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("/database/search") == true {
                return MockURLProtocol.jsonResponse(search, status: searchStatus, for: request)
            }
            return MockURLProtocol.jsonResponse(details, status: detailsStatus, for: request)
        }
    }

    private func expectDiscogsHTTPError(_ expectedCode: Int, _ body: () async throws -> Void) async {
        do {
            try await body()
            Issue.record("应抛出 httpError(\(expectedCode))，但成功返回")
        } catch let error as DiscogsAPIError {
            guard case .httpError(let code) = error else {
                Issue.record("期望 httpError，实际 \(error)")
                return
            }
            #expect(code == expectedCode)
        } catch {
            Issue.record("期望 DiscogsAPIError，实际 \(error)")
        }
    }

    // MARK: - Discogs：搜索与错误路径

    @Test("搜索+详情成功：返回详情艺人，详情请求用 search 的 resource_url")
    func discogsSearchAndDetails() async throws {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-ok"))
        Self.installDiscogsHandler(searchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")]))

        let artist = try await service.searchArtist(name: "Radiohead")

        #expect(artist?.name == "Radiohead")
        #expect(Self.discogsSearchRequests.count == 1)
        #expect(Self.discogsDetailsRequests.count == 1)
        #expect(Self.discogsDetailsRequests.first?.url?.absoluteString == "https://api.discogs.com/artists/1")
        #expect(Self.discogsSearchRequests.first?.value(forHTTPHeaderField: "Authorization") == "Discogs key=fake-key, secret=fake-secret")
    }

    @Test("未配置 key：直接返回 nil，不发任何请求")
    func discogsUnconfigured() async throws {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-unconfigured"), key: nil, secret: nil)

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist == nil)
        #expect(MockURLProtocol.receivedRequests.isEmpty)
    }

    @Test("搜索 500：抛 httpError(500)")
    func discogsSearchError() async {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-search-500"))
        Self.installDiscogsHandler(searchStatus: 500, searchBody: "boom")

        await expectDiscogsHTTPError(500) {
            _ = try await service.searchArtist(name: "Radiohead")
        }
    }

    @Test("详情 404：抛 httpError(404)")
    func discogsDetailsError() async {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-details-404"))
        Self.installDiscogsHandler(searchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")]), detailsStatus: 404)

        await expectDiscogsHTTPError(404) {
            _ = try await service.searchArtist(name: "Radiohead")
        }
    }

    @Test("解码失败：畸形 JSON 抛 DecodingError")
    func discogsDecodeError() async {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-decode"))
        Self.installDiscogsHandler(searchBody: "not-json{{{")

        do {
            _ = try await service.searchArtist(name: "Radiohead")
            Issue.record("畸形 JSON 应解码失败")
        } catch is DecodingError {
            // 现状锁定
        } catch {
            Issue.record("期望 DecodingError，实际 \(error)")
        }
    }

    // MARK: - Discogs：findBestMatch 与缓存

    @Test("findBestMatch：精确匹配（title 全等）")
    func discogsBestMatchExact() async throws {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-exact"))
        Self.installDiscogsHandler(
            searchBody: Self.discogsSearchJSON(results: [(1, "Radiohead"), (2, "Radiohead - Live")]),
            detailsBody: Self.discogsArtistJSON(name: "Radiohead", id: 1)
        )

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist?.id == 1)
        #expect(Self.discogsDetailsRequests.first?.url?.absoluteString == "https://api.discogs.com/artists/1")
    }

    @Test("findBestMatch：无精确匹配回退第一个结果")
    func discogsBestMatchFallback() async throws {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-fallback"))
        Self.installDiscogsHandler(
            searchBody: Self.discogsSearchJSON(results: [(10, "The Beatles"), (11, "Pink Floyd")]),
            detailsBody: Self.discogsArtistJSON(name: "The Beatles", id: 10)
        )

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist?.id == 10) // 第一个结果
    }

    @Test("findBestMatch：部分匹配（子串命中）")
    func discogsBestMatchPartial() async throws {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-partial"))
        Self.installDiscogsHandler(
            searchBody: Self.discogsSearchJSON(results: [(10, "The Beatles"), (11, "Radiohead (Full Album)")]),
            detailsBody: Self.discogsArtistJSON(name: "Radiohead (Full Album)", id: 11)
        )

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist?.id == 11)
    }

    @Test("缓存命中：第二次搜索不请求网络")
    func discogsCacheHit() async throws {
        MockURLProtocol.reset()
        let service = makeDiscogsService(cacheDir: makeTempCacheDir("discogs-cache-hit"))
        Self.installDiscogsHandler(searchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")]))

        let first = try await service.searchArtist(name: "Radiohead")
        #expect(first?.name == "Radiohead")
        #expect(MockURLProtocol.receivedRequests.count == 2) // search + details

        let second = try await service.searchArtist(name: "Radiohead")
        #expect(second?.name == "Radiohead")
        #expect(MockURLProtocol.receivedRequests.count == 2) // 无新增请求
    }

    @Test("过期磁盘缓存：读取即删除，重新拉取")
    func discogsCacheExpiredDeleted() async throws {
        MockURLProtocol.reset()
        let cacheDir = makeTempCacheDir("discogs-cache-expired")
        let service = makeDiscogsService(cacheDir: cacheDir)

        // 预写 8 天前的过期磁盘缓存
        let stale = CachedArtistInfo(
            artistName: "Radiohead",
            discogsArtist: DiscogsArtist(
                id: 999,
                name: "Stale Radiohead",
                resourceUrl: "https://api.discogs.com/artists/999",
                uri: "https://www.discogs.com/artist/999",
                releasesUrl: "https://api.discogs.com/artists/999/releases",
                images: [],
                profile: "stale",
                urls: nil,
                nameVariations: nil,
                aliases: nil,
                members: nil
            ),
            cachedAt: Date().addingTimeInterval(-8 * 24 * 3600)
        )
        let fileURL = cacheDir.appendingPathComponent("radiohead.json")
        try Data(try JSONEncoder().encode(stale)).write(to: fileURL)

        // 详情接口失败 → 搜索抛错；此时过期文件应已被读取删除（cacheArtist 未执行，不会被重新写入）
        Self.installDiscogsHandler(searchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")]), detailsStatus: 500)

        do {
            _ = try await service.searchArtist(name: "Radiohead")
            Issue.record("详情 500 应抛错")
        } catch {
            #expect(!FileManager.default.fileExists(atPath: fileURL.path)) // 过期文件已被清理
            #expect(MockURLProtocol.receivedRequests.count == 2) // 走了网络
        }
    }
}
