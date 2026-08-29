//
//  ArtistNameNormalizer.swift
//  QQPlayer
//
//  歌手名简繁归一（显示层，不动数据库数据）。
//
//  背景：artist 表里同一歌手可能同时有繁体名（周杰倫）和简体名（周杰伦）两行，
//  被当作两个歌手。按当前 UI 语言归一字形：
//  - 简体 UI（zh-Hans）→ 只显示简体名（繁体名归并）
//  - 繁体 UI（zh-Hant）→ 对称
//  - 其他语言（en/ru/fr）→ 不归一（原样）
//  方向由系统语言决定（App 无应用内语言设置）：Bundle.main.preferredLocalizations 首位。
//
//  日文假名不受影响（映射表无假名字符）；日文汉字名在简体 UI 显示简体字形
//  （主流播放器一致做法）。
//
//  映射表：简→繁复用 SimplifiedTraditionalMap.swift 的 simplifiedToTraditionalMap
//  （OpenCC 数据 + 台→台 特例），繁→简由它反转生成，运行时构建一次。
//

import Foundation

/// 歌手名简繁归一工具（纯函数，无状态）
enum ArtistNameNormalizer {
    /// 归一方向
    enum Direction: Equatable, Sendable {
        /// 简体 UI：繁体名归并为简体
        case toSimplified
        /// 繁体 UI：简体名归并为繁体
        case toTraditional
        /// 其他语言：不归一
        case identity
    }

    // MARK: - 方向

    /// 当前 UI 语言决定的归一方向（App 无应用内语言设置，跟随系统）
    static var direction: Direction {
        direction(for: Bundle.main.preferredLocalizations)
    }

    /// 纯函数：由 preferredLocalizations 首位决定方向，便于测试。
    /// zh-Hans* → toSimplified；zh-Hant*/zh-HK/zh-TW/zh-MO → toTraditional；其他 → identity。
    static func direction(for preferredLocalizations: [String]) -> Direction {
        guard let first = preferredLocalizations.first?.lowercased() else { return .identity }
        if first.hasPrefix("zh-hans") { return .toSimplified }
        if first.hasPrefix("zh-hant")
            || first.hasPrefix("zh-hk")
            || first.hasPrefix("zh-tw")
            || first.hasPrefix("zh-mo") {
            return .toTraditional
        }
        return .identity
    }

    // MARK: - 映射

    /// 繁→简单字映射：由 simplifiedToTraditionalMap 反转生成（运行时构建一次）。
    /// "台→台" 特例反转后仍为 台→台，无副作用；源数据为单字→单字，
    /// 反转后一繁→一简，天然安全。
    static let traditionalToSimplifiedMap: [Character: Character] = {
        var map: [Character: Character] = [:]
        map.reserveCapacity(simplifiedToTraditionalMap.count)
        for (simplified, traditional) in simplifiedToTraditionalMap {
            map[traditional] = simplified
        }
        return map
    }()

    // MARK: - 转换

    /// 归一 key（用于分组）：按方向逐字转换；identity 返回原名。
    static func normalizedKey(_ name: String, direction: Direction) -> String {
        switch direction {
        case .toSimplified:
            return String(name.map { traditionalToSimplifiedMap[$0] ?? $0 })
        case .toTraditional:
            return String(name.map { simplifiedToTraditionalMap[$0] ?? $0 })
        case .identity:
            return name
        }
    }

    /// 当前方向下的归一 key
    static func normalizedKey(_ name: String) -> String {
        normalizedKey(name, direction: direction)
    }

    /// 显示名：原名已是目标字形（转换后不变）则保留原名，否则返回转换后的字形。
    static func displayName(_ name: String, direction: Direction) -> String {
        let converted = normalizedKey(name, direction: direction)
        return converted == name ? name : converted
    }

    /// 当前方向下的显示名
    static func displayName(_ name: String) -> String {
        displayName(name, direction: direction)
    }

    /// 组内多名字选显示名：优先组内"原名 == 归一 key"（本来就是目标字形）的名字，
    /// 否则取第一个的转换结果。
    static func displayName(for names: [String], direction: Direction) -> String {
        guard let first = names.first else { return "" }
        if let alreadyTarget = names.first(where: { normalizedKey($0, direction: direction) == $0 }) {
            return alreadyTarget
        }
        return normalizedKey(first, direction: direction)
    }

    /// 当前方向下的组内显示名
    static func displayName(for names: [String]) -> String {
        displayName(for: names, direction: direction)
    }

    // MARK: - 搜索变体

    /// 搜索变体：query 当前字形 + 反向字形各一份，供 SQL LIKE OR 匹配
    /// （简体 UI 下用户输"周杰伦"也能搜到库里的"周傑倫"，反之对称）。
    /// identity 方向只返回原名。
    static func searchVariants(of query: String, direction: Direction) -> [String] {
        guard direction != .identity else { return [query] }
        let toTraditional = String(query.map { simplifiedToTraditionalMap[$0] ?? $0 })
        let toSimplified = String(query.map { traditionalToSimplifiedMap[$0] ?? $0 })
        var variants = [query]
        for variant in [toSimplified, toTraditional] where !variants.contains(variant) {
            variants.append(variant)
        }
        return variants
    }

    /// 当前方向下的搜索变体
    static func searchVariants(of query: String) -> [String] {
        searchVariants(of: query, direction: direction)
    }

    // MARK: - 分组

    /// 歌手列表显示项：一组同字形歌手（displayName + 组内全部 artist id）
    struct NormalizedArtist: Identifiable {
        /// 归一后的显示名
        let displayName: String
        /// 组内全部 artist id（详情聚合曲目用）
        let artistIds: [Int64]
        /// 组内首位歌手（专辑/网络信息等用）
        let primaryArtist: Artist
        /// 组内全部歌手
        let artists: [Artist]

        /// 组内歌手名互不相同（同名即同组），primaryArtist.name 跨组唯一
        var id: String { primaryArtist.name }
    }

    /// 按归一 key 分组（保持输入顺序，即组内首个名字的字母序位置），
    /// 每组一个显示项。
    static func groupedArtists(_ artists: [Artist], direction: Direction) -> [NormalizedArtist] {
        var groups: [String: [Artist]] = [:]
        var order: [String] = []
        for artist in artists {
            let key = normalizedKey(artist.name, direction: direction)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(artist)
        }
        return order.compactMap { key in
            guard let group = groups[key], let primary = group.first else { return nil }
            return NormalizedArtist(
                displayName: displayName(for: group.map(\.name), direction: direction),
                artistIds: group.compactMap(\.id),
                primaryArtist: primary,
                artists: group
            )
        }
    }

    /// 当前方向下按归一 key 分组
    static func groupedArtists(_ artists: [Artist]) -> [NormalizedArtist] {
        groupedArtists(artists, direction: direction)
    }
}
