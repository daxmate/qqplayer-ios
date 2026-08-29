//
//  IdentifiedRowTests.swift
//  QQPlayerTests
//
//  冒烟测试：重复曲目行 ID 去重（ForEach 唯一标识）。
//  同一首歌在队列/歌单出现多次时，rowId 追加 #n，避免 UICollectionView 重复 ID 崩溃。
//

import Testing

@testable import QQPlayer

struct IdentifiedRowTests {
    private func makeTrack(_ stableId: String) -> Track {
        Track(
            stableId: stableId,
            title: "T",
            path: "/tmp/\(stableId).flac"
        )
    }

    @Test("唯一 stableId：rowId 保持原值")
    func uniqueTracksKeepRowId() {
        let tracks = [makeTrack("a"), makeTrack("b"), makeTrack("c")]
        let rows = tracks.uniquelyIdentifiedRows()
        #expect(rows.map(\.rowId) == ["a", "b", "c"])
        #expect(rows.map(\.index) == [0, 1, 2])
    }

    @Test("重复 stableId：第二次起追加 #n，且保持稳定")
    func duplicateTracksGetSuffix() {
        let tracks = [makeTrack("x"), makeTrack("x"), makeTrack("x")]
        let rows = tracks.uniquelyIdentifiedRows()
        #expect(rows.map(\.rowId) == ["x", "x#1", "x#2"])
        // rowId 与 index 无关，只与出现次序有关
        let mixed = [makeTrack("y"), makeTrack("x"), makeTrack("y")]
        let mixedRows = mixed.uniquelyIdentifiedRows()
        #expect(mixedRows.map(\.rowId) == ["y", "x", "y#1"])
    }

    @Test("空数组返回空结果")
    func emptyArray() {
        let rows: [IdentifiedTrackRow] = [Track]().uniquelyIdentifiedRows()
        #expect(rows.isEmpty)
    }

    @Test("rowId 全局唯一（含重复曲目场景）")
    func rowIdsAreUnique() {
        let tracks = [makeTrack("a"), makeTrack("b"), makeTrack("a"), makeTrack("c"), makeTrack("b")]
        let rows = tracks.uniquelyIdentifiedRows()
        #expect(Set(rows.map(\.rowId)).count == rows.count)
    }
}
