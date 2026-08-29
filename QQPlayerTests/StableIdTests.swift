//
//  StableIdTests.swift
//  QQPlayerTests
//
//  冒烟测试：曲库稳定 ID（stableId）生成 —— 局域网同步契约的地基。
//  路径 → SHA256 指纹，必须确定、可区分、标准化。
//

import Foundation
import Testing

@testable import QQPlayer

struct StableIdTests {
    @Test("同一路径生成的 stableId 必须一致（确定性）")
    func deterministic() {
        let path = "/Music/Artist/Album/Track.flac"
        let a = DatabaseManager.generatePathStableId(forPath: path)
        let b = DatabaseManager.generatePathStableId(forPath: path)
        #expect(a == b)
    }

    @Test("不同路径生成的 stableId 必须不同")
    func distinct() {
        let a = DatabaseManager.generatePathStableId(forPath: "/Music/Artist/A.flac")
        let b = DatabaseManager.generatePathStableId(forPath: "/Music/Artist/B.flac")
        #expect(a != b)
    }

    @Test("输出为 64 位小写十六进制（SHA256 指纹）")
    func hexFormat() {
        let id = DatabaseManager.generatePathStableId(forPath: "/tmp/test.flac")
        #expect(id.count == 64)
        #expect(id == id.lowercased())
        #expect(id.allSatisfy { $0.isHexDigit })
    }

    @Test("等价路径（含 . 与 ..）生成相同 stableId")
    func normalizedEquivalentPaths() {
        let a = DatabaseManager.generatePathStableId(forPath: "/tmp/./test.flac")
        let b = DatabaseManager.generatePathStableId(forPath: "/tmp/test.flac")
        #expect(a == b)
    }

    @Test("路径大小写敏感（POSIX 语义，不做小写归一）")
    func caseSensitive() {
        let a = DatabaseManager.generatePathStableId(forPath: "/Music/Track.flac")
        let b = DatabaseManager.generatePathStableId(forPath: "/music/track.flac")
        #expect(a != b)
    }
}
