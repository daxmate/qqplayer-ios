//
//  MusicAPITests.swift
//  QQPlayerTests
//
//  Spotify / Discogs / Hybrid 三件套 API 单元测试（P2-F 补强）：
//  - MockURLProtocol 拦截全部请求，无真实网络
//  - Spotify：token 获取成功 / 401 / 403、token 过期自动刷新、搜索解码现状锁定、findBestMatch、缓存
//  - Discogs：搜索+详情、未配置 key 短路、错误路径、findBestMatch、缓存命中/过期清理
//  - Hybrid：Spotify→Discogs 回退顺序、缓存复用、searchAlternativeArtist、generateNameVariations 确定性
//
//  全部用例放在一个 .serialized 套件里：MockURLProtocol 的 handler / 请求记录是
//  进程级静态状态，跨套件并行执行会互相覆盖。
//

import Foundation
import Testing

@testable import QQPlayer

@Suite(.serialized)
struct MusicAPITests {
    // MARK: - 通用基建

    /// 可变计数/状态盒（Swift 6 逃逸闭包不能直接捕获 var）
    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func makeTempCacheDir(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeSpotifyService(cacheDir: URL) -> SpotifyAPIService {
        SpotifyAPIService(
            clientId: "fake-client",
            clientSecret: "fake-secret",
            session: MockURLProtocol.makeSession(),
            cacheDirectory: cacheDir
        )
    }

    private func makeDiscogsService(cacheDir: URL, key: String? = "fake-key", secret: String? = "fake-secret") -> DiscogsAPIService {
        DiscogsAPIService(
            consumerKey: key,
            consumerSecret: secret,
            session: MockURLProtocol.makeSession(),
            cacheDirectory: cacheDir
        )
    }

    private func makeHybridService(cacheDir: URL) -> HybridMusicAPIService {
        let spotify = SpotifyAPIService(
            clientId: "fake-client",
            clientSecret: "fake-secret",
            session: MockURLProtocol.makeSession(),
            cacheDirectory: cacheDir.appendingPathComponent("spotify", isDirectory: true)
        )
        let discogs = DiscogsAPIService(
            consumerKey: "fake-key",
            consumerSecret: "fake-secret",
            session: MockURLProtocol.makeSession(),
            cacheDirectory: cacheDir.appendingPathComponent("discogs", isDirectory: true)
        )
        return HybridMusicAPIService(
            discogsAPI: discogs,
            spotifyAPI: spotify,
            cacheDirectory: cacheDir.appendingPathComponent("hybrid", isDirectory: true)
        )
    }

    // MARK: - Fixtures：Spotify

    private static let spotifyAuthJSON = #"{"access_token":"test-token-1","token_type":"Bearer","expires_in":3600}"#

    private static func spotifyArtistJSON(name: String, id: String) -> String {
        """
        {"id":"\(id)","name":"\(name)","genres":["alternative rock"],\
        "images":[{"url":"https://img.example/\(id).jpg","height":640,"width":640}],\
        "popularity":80,"followers":{"href":null,"total":1000000},\
        "external_urls":{"spotify":"https://open.spotify.com/artist/\(id)"},\
        "href":"https://api.spotify.com/v1/artists/\(id)","uri":"spotify:artist:\(id)"}
        """
    }

    private static func spotifySearchJSON(artists: [(name: String, id: String)]) -> String {
        let items = artists.map { spotifyArtistJSON(name: $0.name, id: $0.id) }.joined(separator: ",")
        return """
        {"artists":{"href":"https://api.spotify.com/v1/search","items":[\(items)],"limit":10,"next":null,"offset":0,"previous":null,"total":\(artists.count)}}
        """
    }

    private static var spotifyAuthRequests: [URLRequest] {
        MockURLProtocol.receivedRequests.filter {
            $0.url?.absoluteString.hasPrefix("https://accounts.spotify.com/api/token") == true
        }
    }

    private static var spotifySearchRequests: [URLRequest] {
        MockURLProtocol.receivedRequests.filter {
            $0.url?.absoluteString.hasPrefix("https://api.spotify.com/v1/search") == true
        }
    }

    private static func installSpotifyHandler(
        authStatus: Int = 200,
        authBody: String? = nil,
        searchStatus: Int = 200,
        searchBody: String? = nil
    ) {
        let auth = authBody ?? Self.spotifyAuthJSON
        let search = searchBody ?? Self.spotifySearchJSON(artists: [])
        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.hasPrefix("https://accounts.spotify.com/api/token") == true {
                return MockURLProtocol.jsonResponse(auth, status: authStatus, for: request)
            }
            return MockURLProtocol.jsonResponse(search, status: searchStatus, for: request)
        }
    }

    private func expectSpotifyError(_ expected: SpotifyAPIError, _ body: () async throws -> Void) async {
        do {
            try await body()
            Issue.record("应抛出 \(expected)，但成功返回")
        } catch let error as SpotifyAPIError {
            switch (expected, error) {
            case (.httpError(let expectedCode), .httpError(let actualCode)):
                #expect(expectedCode == actualCode)
            case (.forbidden(let expectedBody), .forbidden(let actualBody)):
                #expect(expectedBody == actualBody)
            default:
                Issue.record("错误不匹配：期望 \(expected)，实际 \(error)")
            }
        } catch {
            Issue.record("错误类型不匹配：期望 SpotifyAPIError，实际 \(error)")
        }
    }

    // MARK: - Fixtures：Discogs

    private static func discogsSearchJSON(results: [(id: Int, title: String)]) -> String {
        let items = results.map { result -> String in
            """
            {"id":\(result.id),"type":"artist","user_data":null,"master_id":null,"master_url":null,\
            "uri":"https://www.discogs.com/artist/\(result.id)","title":"\(result.title)",\
            "thumb":"https://img.example/t\(result.id).jpg","cover_image":"https://img.example/c\(result.id).jpg",\
            "resource_url":"https://api.discogs.com/artists/\(result.id)"}
            """
        }.joined(separator: ",")
        return """
        {"pagination":{"page":1,"pages":1,"per_page":5,"items":\(results.count),"urls":null},"results":[\(items)]}
        """
    }

    private static func discogsArtistJSON(name: String, id: Int = 1) -> String {
        """
        {"id":\(id),"name":"\(name)","resource_url":"https://api.discogs.com/artists/\(id)",\
        "uri":"https://www.discogs.com/artist/\(id)","releases_url":"https://api.discogs.com/artists/\(id)/releases",\
        "images":[{"type":"primary","uri":"https://img.example/\(id).jpg","resource_url":"https://img.example/\(id).jpg",\
        "uri150":"https://img.example/\(id)-150.jpg","width":600,"height":600}],\
        "profile":"English rock band","urls":null,"namevariations":null,"aliases":null,"members":null}
        """
    }

    private static var discogsSearchRequests: [URLRequest] {
        MockURLProtocol.receivedRequests.filter {
            $0.url?.absoluteString.contains("/database/search") == true
        }
    }

    private static var discogsDetailsRequests: [URLRequest] {
        MockURLProtocol.receivedRequests.filter {
            $0.url?.absoluteString.contains("/artists/") == true
        }
    }

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

    // MARK: - Fixtures：Hybrid

    private static func installHybridHandler(
        spotifySearchBody: String,
        discogsSearchBody: String,
        spotifyAuthStatus: Int = 200,
        discogsDetailsStatus: Int = 200,
        discogsDetailsBody: String? = nil
    ) {
        let details = discogsDetailsBody ?? Self.discogsArtistJSON(name: "Radiohead", id: 1)
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasPrefix("https://accounts.spotify.com/api/token") {
                return MockURLProtocol.jsonResponse(Self.spotifyAuthJSON, status: spotifyAuthStatus, for: request)
            }
            if url.hasPrefix("https://api.spotify.com/v1/search") {
                return MockURLProtocol.jsonResponse(spotifySearchBody, for: request)
            }
            if url.contains("/database/search") {
                return MockURLProtocol.jsonResponse(discogsSearchBody, for: request)
            }
            return MockURLProtocol.jsonResponse(details, status: discogsDetailsStatus, for: request)
        }
    }

    // MARK: - Spotify：token 获取

    @Test("token 获取成功：搜索携带 Bearer token 并返回匹配艺人")
    func spotifyAuthSuccess() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-auth-ok"))
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")]))

        let artist = try await service.searchArtist(name: "Radiohead")

        #expect(artist?.name == "Radiohead")
        #expect(Self.spotifyAuthRequests.count == 1)
        // Basic base64("fake-client:fake-secret")
        let expected = "Basic " + Data("fake-client:fake-secret".utf8).base64EncodedString()
        #expect(Self.spotifyAuthRequests.first?.value(forHTTPHeaderField: "Authorization") == expected)
        #expect(Self.spotifySearchRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-1")
    }

    @Test("认证接口 401：抛 httpError(401)，不再发起搜索")
    func spotifyAuth401() async {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-auth-401"))
        Self.installSpotifyHandler(authStatus: 401, authBody: #"{"error":"invalid_client"}"#)

        await expectSpotifyError(.httpError(401)) {
            _ = try await service.searchArtist(name: "Radiohead")
        }
        #expect(Self.spotifyAuthRequests.count == 1)
        #expect(Self.spotifySearchRequests.isEmpty)
    }

    @Test("认证接口 403：抛 httpError(403)")
    func spotifyAuth403() async {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-auth-403"))
        Self.installSpotifyHandler(authStatus: 403, authBody: #"{"error":"forbidden"}"#)

        await expectSpotifyError(.httpError(403)) {
            _ = try await service.searchArtist(name: "Radiohead")
        }
    }

    @Test("token 过期后自动刷新：两次搜索分别使用新 token")
    func spotifyTokenRefresh() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-refresh"))

        // expires_in=59 → expiresAt 取 now-1s，立即视为过期 → 每次搜索都会重新取 token
        let authCalls = Box(0)
        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.hasPrefix("https://accounts.spotify.com/api/token") == true {
                authCalls.value += 1
                let body = #"{"access_token":"tok-\#(authCalls.value)","token_type":"Bearer","expires_in":59}"#
                return MockURLProtocol.jsonResponse(body, for: request)
            }
            return MockURLProtocol.jsonResponse(Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")]), for: request)
        }

        let first = try await service.searchArtist(name: "Radiohead")
        #expect(first?.name == "Radiohead")
        let second = try await service.searchArtist(name: "Radiohead II") // 不同名字避开艺人缓存
        #expect(second?.name == "Radiohead")

        #expect(Self.spotifyAuthRequests.count == 2)
        #expect(Self.spotifySearchRequests.count == 2)
        // 第二次搜索必须使用刷新后的 token
        #expect(Self.spotifySearchRequests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
    }

    @Test("token 未过期：连续搜索只获取一次 token")
    func spotifyTokenReuse() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-reuse"))
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")]))

        _ = try await service.searchArtist(name: "Radiohead")
        _ = try await service.searchArtist(name: "Coldplay")

        #expect(Self.spotifyAuthRequests.count == 1)
        #expect(Self.spotifySearchRequests.count == 2)
    }

    @Test("搜索接口 401：抛 httpError(401)，不触发 token 刷新（锁现状）")
    func spotifySearch401DoesNotRefresh() async {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-search-401"))
        Self.installSpotifyHandler(searchStatus: 401, searchBody: #"{"error":{"message":"Invalid access token"}}"#)

        await expectSpotifyError(.httpError(401)) {
            _ = try await service.searchArtist(name: "Radiohead")
        }
        #expect(Self.spotifyAuthRequests.count == 1) // 只取了一次 token，没有刷新重试
    }

    @Test("搜索接口 403：抛 forbidden 并携带响应体")
    func spotifySearch403Forbidden() async {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-search-403"))
        Self.installSpotifyHandler(searchStatus: 403, searchBody: #"{"error":"rate limited"}"#)

        await expectSpotifyError(.forbidden(#"{"error":"rate limited"}"#)) {
            _ = try await service.searchArtist(name: "Radiohead")
        }
    }

    // MARK: - Spotify：搜索解码

    @Test("搜索解码：缺少必填字段抛 DecodingError（现状：字段全非 Optional）")
    func spotifyDecodeMissingField() async {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-decode"))
        // 艺人对象缺 popularity（当前模型非 Optional，缺失即解码失败）——锁现状
        let malformed = """
        {"artists":{"href":"h","items":[{"id":"id-1","name":"Radiohead","genres":[],"images":[],\
        "followers":{"href":null,"total":1},"external_urls":{"spotify":"s"},"href":"h","uri":"u"}],\
        "limit":10,"next":null,"offset":0,"previous":null,"total":1}}
        """
        Self.installSpotifyHandler(searchBody: malformed)

        do {
            _ = try await service.searchArtist(name: "Radiohead")
            Issue.record("缺少 popularity 字段应解码失败")
        } catch is DecodingError {
            // 现状锁定：解码失败直接抛出
        } catch {
            Issue.record("期望 DecodingError，实际 \(error)")
        }
    }

    // MARK: - Spotify：findBestMatch

    @Test("findBestMatch：精确匹配优先于部分匹配")
    func spotifyBestMatchExactWins() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-exact"))
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: [("Radiohead - Live", "id-1"), ("Radiohead", "id-2")]))

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist?.id == "id-2")
    }

    @Test("findBestMatch：大小写与标点归一后可精确匹配")
    func spotifyBestMatchNormalization() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-norm"))
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: [("Radiohead", "id-1")]))

        let artist = try await service.searchArtist(name: "RADIOHEAD.")
        #expect(artist?.id == "id-1")
    }

    @Test("findBestMatch：无精确匹配时部分匹配（子串命中）")
    func spotifyBestMatchPartial() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-partial"))
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: [("The Beatles", "id-1"), ("Radiohead in Concert", "id-2")]))

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist?.id == "id-2")
    }

    @Test("findBestMatch：无匹配时回退第一个结果")
    func spotifyBestMatchFallsBackToFirst() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-fallback"))
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: [("The Beatles", "id-1"), ("Pink Floyd", "id-2")]))

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist?.id == "id-1")
    }

    @Test("findBestMatch：空结果返回 nil")
    func spotifyBestMatchNoResults() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-empty"))
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: []))

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist == nil)
    }

    // MARK: - Spotify：缓存

    @Test("缓存命中：第二次搜索不发起网络请求")
    func spotifyCacheHit() async throws {
        MockURLProtocol.reset()
        let service = makeSpotifyService(cacheDir: makeTempCacheDir("spotify-cache-hit"))
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: [("Adele", "id-adele")]))

        let first = try await service.searchArtist(name: "Adele")
        #expect(first?.id == "id-adele")
        #expect(MockURLProtocol.receivedRequests.count == 2) // auth + search

        let second = try await service.searchArtist(name: "Adele")
        #expect(second?.id == "id-adele")
        #expect(MockURLProtocol.receivedRequests.count == 2) // 无新增请求
    }

    @Test("过期磁盘缓存：不命中，重新拉取并覆盖")
    func spotifyCacheExpiredRefetches() async throws {
        MockURLProtocol.reset()
        let cacheDir = makeTempCacheDir("spotify-cache-expired")
        let service = makeSpotifyService(cacheDir: cacheDir)
        Self.installSpotifyHandler(searchBody: Self.spotifySearchJSON(artists: [("Adele", "id-adele")]))

        // 预写一份 8 天前的过期磁盘缓存（同构 Codable，直接落盘）
        let stale = CachedSpotifyArtistInfo(
            artistName: "Adele",
            spotifyArtist: Self.staleSpotifyArtist(),
            cachedAt: Date().addingTimeInterval(-8 * 24 * 3600)
        )
        let fileURL = cacheDir.appendingPathComponent("adele.json")
        try Data(try JSONEncoder().encode(stale)).write(to: fileURL)

        let artist = try await service.searchArtist(name: "Adele")

        #expect(artist?.name == "Adele") // 新鲜结果，而非过期数据
        #expect(MockURLProtocol.receivedRequests.count == 2) // 走了网络

        // 磁盘缓存被新数据覆盖
        let refreshed = try JSONDecoder().decode(CachedSpotifyArtistInfo.self, from: Data(contentsOf: fileURL))
        #expect(refreshed.spotifyArtist.name == "Adele")
        #expect(refreshed.cachedAt > Date().addingTimeInterval(-60))
    }

    private static func staleSpotifyArtist() -> SpotifyArtist {
        SpotifyArtist(
            id: "id-stale",
            name: "Stale Adele",
            genres: [],
            images: [],
            popularity: 1,
            followers: SpotifyFollowers(href: nil, total: 1),
            externalUrls: SpotifyExternalUrls(spotify: "https://open.spotify.com/artist/id-stale"),
            href: "https://api.spotify.com/v1/artists/id-stale",
            uri: "spotify:artist:id-stale"
        )
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

    // MARK: - Hybrid：回退顺序

    @Test("回退顺序：Spotify 命中则用 Spotify，不查 Discogs")
    func hybridPrefersSpotify() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-spotify-first"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")]),
            discogsSearchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")])
        )

        let artist = try await service.searchArtist(name: "Radiohead")

        #expect(artist?.source == .spotify)
        #expect(artist?.name == "Radiohead")
        #expect(Self.spotifySearchRequests.count == 1)
        #expect(Self.discogsSearchRequests.isEmpty) // Discogs 未被查询
    }

    @Test("回退顺序：Spotify 无结果时回退 Discogs")
    func hybridFallsBackToDiscogs() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-fallback"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: []),
            discogsSearchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")])
        )

        let artist = try await service.searchArtist(name: "Radiohead")

        #expect(artist?.source == .discogs)
        #expect(artist?.name == "Radiohead")
        #expect(Self.spotifySearchRequests.count == 1)
        #expect(Self.discogsSearchRequests.count == 1)
        #expect(Self.discogsDetailsRequests.count == 1)
    }

    @Test("回退顺序：Spotify 抛错时回退 Discogs")
    func hybridFallsBackWhenSpotifyThrows() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-fallback-error"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")]),
            discogsSearchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")]),
            spotifyAuthStatus: 500
        )

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist?.source == .discogs)
    }

    @Test("两平台都无结果：返回 nil")
    func hybridBothEmpty() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-both-empty"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: []),
            discogsSearchBody: Self.discogsSearchJSON(results: [])
        )

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist == nil)
    }

    @Test("两平台都抛错：返回 nil（错误被吞掉）")
    func hybridBothFail() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-both-fail"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: []),
            discogsSearchBody: "not-json", // Discogs 解码失败
            spotifyAuthStatus: 500
        )

        let artist = try await service.searchArtist(name: "Radiohead")
        #expect(artist == nil)
    }

    // MARK: - Hybrid：缓存复用

    @Test("缓存命中（Spotify 源）：第二次不请求网络")
    func hybridCacheHitSpotify() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-cache-spotify"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")]),
            discogsSearchBody: Self.discogsSearchJSON(results: [])
        )

        let first = try await service.searchArtist(name: "Radiohead")
        #expect(first?.source == .spotify)
        let requestsAfterFirst = MockURLProtocol.receivedRequests.count

        let second = try await service.searchArtist(name: "Radiohead")
        #expect(second?.source == .spotify)
        #expect(MockURLProtocol.receivedRequests.count == requestsAfterFirst) // 无新增请求
    }

    @Test("缓存 Discogs 源：仍先查 Spotify，未命中才复用缓存（不再查 Discogs）")
    func hybridCachedDiscogsRechecksSpotify() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-cache-discogs"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: []),
            discogsSearchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")])
        )

        let first = try await service.searchArtist(name: "Radiohead")
        #expect(first?.source == .discogs)

        let requestsAfterFirst = MockURLProtocol.receivedRequests.count
        let discogsSearchesAfterFirst = Self.discogsSearchRequests.count

        let second = try await service.searchArtist(name: "Radiohead")
        #expect(second?.source == .discogs) // 复用缓存
        #expect(Self.spotifySearchRequests.count == 2) // 又查了一次 Spotify
        #expect(Self.discogsSearchRequests.count == discogsSearchesAfterFirst) // Discogs 未再查询
        #expect(MockURLProtocol.receivedRequests.count == requestsAfterFirst + 1) // 只新增 1 次 Spotify 搜索
    }

    // MARK: - Hybrid：searchAlternativeArtist

    @Test("searchAlternativeArtist：Spotify 源时只查 Discogs")
    func hybridAlternativeFromSpotify() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-alt-spotify"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")]),
            discogsSearchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")])
        )

        let artist = try await service.searchAlternativeArtist(name: "Radiohead", currentSource: .spotify)

        #expect(artist?.source == .discogs)
        #expect(Self.spotifySearchRequests.isEmpty) // 不查 Spotify
        #expect(Self.discogsSearchRequests.count == 1)
    }

    @Test("searchAlternativeArtist：Discogs 源时只查 Spotify")
    func hybridAlternativeFromDiscogs() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-alt-discogs"))
        Self.installHybridHandler(
            spotifySearchBody: Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")]),
            discogsSearchBody: Self.discogsSearchJSON(results: [(1, "Radiohead")])
        )

        let artist = try await service.searchAlternativeArtist(name: "Radiohead", currentSource: .discogs)

        #expect(artist?.source == .spotify)
        #expect(Self.discogsSearchRequests.isEmpty)
        #expect(Self.spotifySearchRequests.count == 1)
    }

    // MARK: - Hybrid：generateNameVariations 确定性

    @Test("generateNameVariations：确定性——两次调用结果完全一致")
    func nameVariationsDeterministic() {
        let service = makeHybridService(cacheDir: makeTempCacheDir("variations-deterministic"))

        let input = "Artist (Live) - Topic"
        let first = service.generateNameVariations(input)
        let second = service.generateNameVariations(input)
        #expect(first == second)
    }

    @Test("generateNameVariations：去掉常见后缀与括号内容，保持生成顺序")
    func nameVariationsOrderAndDedup() {
        let service = makeHybridService(cacheDir: makeTempCacheDir("variations-order"))

        #expect(service.generateNameVariations("Radiohead - Topic") == ["Radiohead", "The Radiohead - Topic"])
        // 去 "The" 前缀从完整原名上做 dropFirst，括号内容保留
        #expect(service.generateNameVariations("The Beatles (Remastered)") == ["The Beatles", "Beatles (Remastered)"])
        // 括号正则只删括号内容不折叠内部空白（现状锁定）
        #expect(service.generateNameVariations("Artist (Live) - Topic") == ["Artist (Live)", "Artist  - Topic", "The Artist (Live) - Topic"])
    }

    @Test("generateNameVariations：去重且最多 3 个")
    func nameVariationsDedupAndLimit() {
        let service = makeHybridService(cacheDir: makeTempCacheDir("variations-limit"))

        let variations = service.generateNameVariations("X - Topic (Official)")
        #expect(variations.count <= 3)
        #expect(variations.count == Set(variations).count) // 无重复
        #expect(variations.contains("X - Topic")) // 括号清理与后缀清理产出的重复项被去重
    }

    @Test("searchSimilarArtist：按变体顺序尝试，首个命中即返回")
    func hybridSearchSimilar() async throws {
        MockURLProtocol.reset()
        let service = makeHybridService(cacheDir: makeTempCacheDir("hybrid-similar"))

        // "Radiohead - Topic" → 变体 ["Radiohead", "The Radiohead - Topic"]（跳过原词），
        // 只有 "Radiohead" 有结果 → 第二个变体不应被查询
        let hitJSON = Self.spotifySearchJSON(artists: [("Radiohead", "id-rh")])
        let missJSON = Self.spotifySearchJSON(artists: [])
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasPrefix("https://accounts.spotify.com/api/token") {
                return MockURLProtocol.jsonResponse(Self.spotifyAuthJSON, for: request)
            }
            if url.hasPrefix("https://api.spotify.com/v1/search") {
                let query = url.components(separatedBy: "q=").last ?? ""
                return MockURLProtocol.jsonResponse(query.hasPrefix("Radiohead&") ? hitJSON : missJSON, for: request)
            }
            if url.contains("/database/search") {
                return MockURLProtocol.jsonResponse(missJSON, for: request)
            }
            return MockURLProtocol.jsonResponse(Self.discogsArtistJSON(name: "x", id: 1), for: request)
        }

        let artist = try await service.searchSimilarArtist(originalName: "Radiohead - Topic", currentSource: nil)

        #expect(artist?.name == "Radiohead")
        #expect(artist?.source == .spotify)
        #expect(Self.spotifySearchRequests.count == 1) // 只查询了第一个变体 "Radiohead"
    }
}
