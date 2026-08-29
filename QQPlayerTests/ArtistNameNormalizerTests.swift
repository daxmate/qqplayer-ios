//
//  ArtistNameNormalizerTests.swift
//  QQPlayerTests
//
//  歌手名简繁归一纯逻辑测试：
//  - 方向判断（zh-Hans/zh-Hant/其他 → toSimplified/toTraditional/identity）
//  - normalizedKey / displayName 的字形转换（繁体归并、日文假名不受影响、
//    日文汉字转简体、ASCII 不变、台→台 特例）
//  - displayName(for:) 组内显示名选择逻辑
//  - searchVariants 双向字形变体
//  - groupedArtists 同名简繁两行归并
//  注：getTracksByArtistIds 依赖 DatabaseManager 单例（private init + 私有
//  dbWriter），无内存 DB 测试缝，未直接单测（由 xcodebuild 编译 + 详情页
//  聚合路径覆盖）。
//

import Foundation
import Testing

@testable import QQPlayer

struct ArtistNameNormalizerTests {
    // MARK: - 方向判断（纯函数）

    @Test("zh-Hans → toSimplified")
    func directionSimplified() {
        #expect(ArtistNameNormalizer.direction(for: ["zh-Hans"]) == .toSimplified)
        #expect(ArtistNameNormalizer.direction(for: ["zh-Hans-CN"]) == .toSimplified)
        #expect(ArtistNameNormalizer.direction(for: ["zh-Hans", "en"]) == .toSimplified)
    }

    @Test("zh-Hant/zh-HK/zh-TW → toTraditional")
    func directionTraditional() {
        #expect(ArtistNameNormalizer.direction(for: ["zh-Hant"]) == .toTraditional)
        #expect(ArtistNameNormalizer.direction(for: ["zh-Hant-TW"]) == .toTraditional)
        #expect(ArtistNameNormalizer.direction(for: ["zh-HK"]) == .toTraditional)
        #expect(ArtistNameNormalizer.direction(for: ["zh-TW"]) == .toTraditional)
    }

    @Test("其他语言/空列表 → identity")
    func directionIdentity() {
        #expect(ArtistNameNormalizer.direction(for: ["en"]) == .identity)
        #expect(ArtistNameNormalizer.direction(for: ["ru"]) == .identity)
        #expect(ArtistNameNormalizer.direction(for: ["fr", "zh-Hans"]) == .identity) // 只看首位
        #expect(ArtistNameNormalizer.direction(for: []) == .identity)
    }

    // MARK: - normalizedKey

    @Test("toSimplified：繁体名归并为简体")
    func keyToSimplified() {
        #expect(ArtistNameNormalizer.normalizedKey("周杰倫", direction: .toSimplified) == "周杰伦")
        #expect(ArtistNameNormalizer.normalizedKey("周杰伦", direction: .toSimplified) == "周杰伦") // 已是简体不变
        #expect(ArtistNameNormalizer.normalizedKey("鄧紫棋", direction: .toSimplified) == "邓紫棋")
    }

    @Test("toTraditional：简体名归并为繁体")
    func keyToTraditional() {
        #expect(ArtistNameNormalizer.normalizedKey("周杰伦", direction: .toTraditional) == "周傑倫")
        // 混合字形（含简体字）也归一为全繁体
        #expect(ArtistNameNormalizer.normalizedKey("周杰倫", direction: .toTraditional) == "周傑倫")
    }

    @Test("日文假名不受影响（映射表无假名字符）")
    func kanaUnchanged() {
        #expect(ArtistNameNormalizer.normalizedKey("宇多田ヒカル", direction: .toSimplified) == "宇多田ヒカル")
        #expect(ArtistNameNormalizer.normalizedKey("宇多田ヒカル", direction: .toTraditional) == "宇多田ヒカル")
    }

    @Test("日文汉字：简体 UI 显示简体字形")
    func japaneseKanji() {
        #expect(ArtistNameNormalizer.normalizedKey("中島美嘉", direction: .toSimplified) == "中岛美嘉")
        #expect(ArtistNameNormalizer.normalizedKey("中島美嘉", direction: .toTraditional) == "中島美嘉")
    }

    @Test("ASCII/英文名不受影响")
    func asciiUnchanged() {
        #expect(ArtistNameNormalizer.normalizedKey("Adele", direction: .toSimplified) == "Adele")
        #expect(ArtistNameNormalizer.normalizedKey("Adele", direction: .toTraditional) == "Adele")
    }

    @Test("identity 方向原样返回")
    func identityUnchanged() {
        #expect(ArtistNameNormalizer.normalizedKey("周杰倫", direction: .identity) == "周杰倫")
        #expect(ArtistNameNormalizer.normalizedKey("周杰伦", direction: .identity) == "周杰伦")
    }

    @Test("台→台 特例反转后仍稳定")
    func taiwanSpecialCase() {
        #expect(ArtistNameNormalizer.normalizedKey("電台", direction: .toSimplified) == "电台")
        #expect(ArtistNameNormalizer.normalizedKey("电台", direction: .toTraditional) == "電台")
    }

    // MARK: - displayName

    @Test("displayName：原名已是目标字形则保留原名，否则返回转换结果")
    func displayNameSingle() {
        #expect(ArtistNameNormalizer.displayName("周杰倫", direction: .toSimplified) == "周杰伦")
        #expect(ArtistNameNormalizer.displayName("周杰伦", direction: .toSimplified) == "周杰伦")
        #expect(ArtistNameNormalizer.displayName("周杰伦", direction: .toTraditional) == "周傑倫")
        // 混合字形（含简体字）→ 转换为全繁体
        #expect(ArtistNameNormalizer.displayName("周杰倫", direction: .toTraditional) == "周傑倫")
        #expect(ArtistNameNormalizer.displayName("Adele", direction: .toSimplified) == "Adele")
    }

    @Test("displayName(for:)：优先组内本来就是目标字形的名字")
    func displayNameForGroup() {
        // 简体 UI：组内有简体名 → 用它
        #expect(ArtistNameNormalizer.displayName(for: ["周杰倫", "周杰伦"], direction: .toSimplified) == "周杰伦")
        // 简体 UI：组内全是繁体 → 取第一个的转换结果
        #expect(ArtistNameNormalizer.displayName(for: ["周杰倫"], direction: .toSimplified) == "周杰伦")
        // 繁体 UI 对称
        #expect(ArtistNameNormalizer.displayName(for: ["周杰伦", "周傑倫"], direction: .toTraditional) == "周傑倫")
        #expect(ArtistNameNormalizer.displayName(for: ["周杰伦"], direction: .toTraditional) == "周傑倫")
        // identity：取第一个原名
        #expect(ArtistNameNormalizer.displayName(for: ["周杰倫", "周杰伦"], direction: .identity) == "周杰倫")
        // 空组
        #expect(ArtistNameNormalizer.displayName(for: [], direction: .toSimplified).isEmpty)
    }

    // MARK: - searchVariants

    @Test("searchVariants：简体方向同时生成繁体变体")
    func searchVariantsSimplified() {
        let variants = ArtistNameNormalizer.searchVariants(of: "周杰伦", direction: .toSimplified)
        #expect(variants.contains("周杰伦"))
        #expect(variants.contains("周傑倫"))
    }

    @Test("searchVariants：繁体方向同时生成简体变体")
    func searchVariantsTraditional() {
        let variants = ArtistNameNormalizer.searchVariants(of: "周杰倫", direction: .toTraditional)
        #expect(variants.contains("周杰倫"))
        #expect(variants.contains("周杰伦"))
    }

    @Test("searchVariants：identity 只返回原名")
    func searchVariantsIdentity() {
        #expect(ArtistNameNormalizer.searchVariants(of: "周杰伦", direction: .identity) == ["周杰伦"])
    }

    // MARK: - groupedArtists

    @Test("groupedArtists：同名简繁两行归为一组（保持输入顺序）")
    func groupedArtistsMerge() {
        let simplified = Artist(id: 1, name: "周杰伦")
        let traditional = Artist(id: 2, name: "周傑倫")
        let adele = Artist(id: 3, name: "Adele")

        let groups = ArtistNameNormalizer.groupedArtists([traditional, simplified, adele], direction: .toSimplified)
        #expect(groups.count == 2)

        let jayGroup = groups.first { $0.displayName == "周杰伦" }
        #expect(jayGroup != nil)
        #expect(jayGroup?.primaryArtist.name == "周傑倫") // 组内首位
        #expect(jayGroup?.artistIds == [2, 1])           // 组内全部 id
        #expect(jayGroup?.artists.count == 2)

        let adeleGroup = groups.first { $0.displayName == "Adele" }
        #expect(adeleGroup?.artistIds == [3])
    }

    @Test("groupedArtists：identity 方向不合并")
    func groupedArtistsIdentity() {
        let simplified = Artist(id: 1, name: "周杰伦")
        let traditional = Artist(id: 2, name: "周傑倫")
        let groups = ArtistNameNormalizer.groupedArtists([simplified, traditional], direction: .identity)
        #expect(groups.count == 2)
    }

    @Test("groupedArtists：日文名独立成组（假名不参与简繁映射）")
    func groupedArtistsKanaSeparate() {
        let a = Artist(id: 1, name: "宇多田ヒカル")
        let groups = ArtistNameNormalizer.groupedArtists([a], direction: .toSimplified)
        #expect(groups.count == 1)
        #expect(groups[0].displayName == "宇多田ヒカル")
    }
}
