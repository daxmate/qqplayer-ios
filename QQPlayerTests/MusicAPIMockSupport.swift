//
//  MusicAPIMockSupport.swift
//  QQPlayerTests
//
//  MusicAPITests 拆分后的公共骨架与共享基建（原 MusicAPITests.swift 拆分）：
//  - @Suite(.serialized) struct MusicAPITests 骨架：拆分后 Spotify / Discogs / Hybrid
//    三组用例仍是同一个 .serialized 套件。MockURLProtocol 的 handler / 请求记录是
//    进程级静态状态，若拆成多个独立套件会跨套件并行执行互相覆盖（.serialized
//    只约束套件内部），所以各组用例以 extension MusicAPITests 的形式拆到
//    SpotifyAPITests.swift / DiscogsAPITests.swift / HybridMusicAPITests.swift。
//  - Box / makeTempCacheDir / 三个 service 工厂（makeSpotifyService / makeDiscogsService / makeHybridService）
//  - 跨 API 共享的 JSON fixture 与请求过滤器（Spotify / Discogs / Hybrid 用例均引用）
//

import Foundation
import Testing

@testable import QQPlayer

/// 可变计数/状态盒（Swift 6 逃逸闭包不能直接捕获 var）
final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// API 测试套件骨架：三组用例以 extension 形式分布在各拆分文件中。
@Suite(.serialized)
struct MusicAPITests {}

extension MusicAPITests {
    // MARK: - 通用基建

    func makeTempCacheDir(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func makeSpotifyService(cacheDir: URL) -> SpotifyAPIService {
        SpotifyAPIService(
            clientId: "fake-client",
            clientSecret: "fake-secret",
            session: MockURLProtocol.makeSession(),
            cacheDirectory: cacheDir
        )
    }

    func makeDiscogsService(cacheDir: URL, key: String? = "fake-key", secret: String? = "fake-secret") -> DiscogsAPIService {
        DiscogsAPIService(
            consumerKey: key,
            consumerSecret: secret,
            session: MockURLProtocol.makeSession(),
            cacheDirectory: cacheDir
        )
    }

    func makeHybridService(cacheDir: URL) -> HybridMusicAPIService {
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

    // MARK: - Fixtures：Spotify（跨文件共享）

    static let spotifyAuthJSON = #"{"access_token":"test-token-1","token_type":"Bearer","expires_in":3600}"#

    static func spotifySearchJSON(artists: [(name: String, id: String)]) -> String {
        let items = artists.map { spotifyArtistJSON(name: $0.name, id: $0.id) }.joined(separator: ",")
        return """
        {"artists":{"href":"https://api.spotify.com/v1/search","items":[\(items)],"limit":10,"next":null,"offset":0,"previous":null,"total":\(artists.count)}}
        """
    }

    private static func spotifyArtistJSON(name: String, id: String) -> String {
        """
        {"id":"\(id)","name":"\(name)","genres":["alternative rock"],\
        "images":[{"url":"https://img.example/\(id).jpg","height":640,"width":640}],\
        "popularity":80,"followers":{"href":null,"total":1000000},\
        "external_urls":{"spotify":"https://open.spotify.com/artist/\(id)"},\
        "href":"https://api.spotify.com/v1/artists/\(id)","uri":"spotify:artist:\(id)"}
        """
    }

    static var spotifyAuthRequests: [URLRequest] {
        MockURLProtocol.receivedRequests.filter {
            $0.url?.absoluteString.hasPrefix("https://accounts.spotify.com/api/token") == true
        }
    }

    static var spotifySearchRequests: [URLRequest] {
        MockURLProtocol.receivedRequests.filter {
            $0.url?.absoluteString.hasPrefix("https://api.spotify.com/v1/search") == true
        }
    }

    // MARK: - Fixtures：Discogs（跨文件共享）

    static func discogsSearchJSON(results: [(id: Int, title: String)]) -> String {
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

    static func discogsArtistJSON(name: String, id: Int = 1) -> String {
        """
        {"id":\(id),"name":"\(name)","resource_url":"https://api.discogs.com/artists/\(id)",\
        "uri":"https://www.discogs.com/artist/\(id)","releases_url":"https://api.discogs.com/artists/\(id)/releases",\
        "images":[{"type":"primary","uri":"https://img.example/\(id).jpg","resource_url":"https://img.example/\(id).jpg",\
        "uri150":"https://img.example/\(id)-150.jpg","width":600,"height":600}],\
        "profile":"English rock band","urls":null,"namevariations":null,"aliases":null,"members":null}
        """
    }

    static var discogsSearchRequests: [URLRequest] {
        MockURLProtocol.receivedRequests.filter {
            $0.url?.absoluteString.contains("/database/search") == true
        }
    }

    static var discogsDetailsRequests: [URLRequest] {
        MockURLProtocol.receivedRequests.filter {
            $0.url?.absoluteString.contains("/artists/") == true
        }
    }
}
