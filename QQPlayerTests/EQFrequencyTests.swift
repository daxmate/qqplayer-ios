//
//  EQFrequencyTests.swift
//  QQPlayerTests
//
//  均衡器参数式预设默认频率：对数分布（20Hz - 20kHz），带边界裁剪。
//

import Foundation
import Testing

@testable import QQPlayer

@MainActor
struct EQFrequencyTests {
    @Test("bandCount 为 0 或负数时返回空数组")
    func emptyForNonPositive() {
        #expect(EQManager.defaultParametricFrequencies(for: 0).isEmpty)
        #expect(EQManager.defaultParametricFrequencies(for: -3).isEmpty)
    }

    @Test("单 band 时返回中频 1000Hz")
    func singleBand() {
        #expect(EQManager.defaultParametricFrequencies(for: 1) == [1000.0])
    }

    @Test("bandCount 超过 16 时裁剪到 16")
    func clampTo16() {
        #expect(EQManager.defaultParametricFrequencies(for: 16).count == 16)
        #expect(EQManager.defaultParametricFrequencies(for: 32).count == 16)
        #expect(EQManager.defaultParametricFrequencies(for: 100).count == 16)
    }

    @Test("频率单调递增")
    func monotonicallyIncreasing() {
        let freqs = EQManager.defaultParametricFrequencies(for: 10)
        #expect(freqs == freqs.sorted())
        #expect(Set(freqs).count == freqs.count)
    }

    @Test("频率范围在 20Hz - 20kHz 内")
    func rangeBounds() {
        let freqs = EQManager.defaultParametricFrequencies(for: 10)
        #expect(freqs.first! >= 20.0)
        #expect(freqs.last! <= 20_000.0)
        #expect(freqs.last! > freqs.first!)
    }

    @Test("首尾接近对数端点（20Hz 与 20kHz）")
    func endpoints() {
        let freqs = EQManager.defaultParametricFrequencies(for: 10)
        #expect(abs(freqs.first! - 20.0) < 1.0)
        #expect(abs(freqs.last! - 20_000.0) < 1.0)
    }
}
