//
//  BuiltinEQPresets.swift
//  QQPlayer
//
//  10 段经典图形 EQ 预设（照搬桌面端 frontend/src/composables/useEq.ts）
//  频点与增益数值与桌面端保持一致，勿改。
//

import Foundation

struct BuiltinEQPreset {
    /// 稳定标识（flat/pop/rock/jazz/classical/bass/vocal）
    let key: String
    /// 本地化 key（Localizable.strings）
    let nameKey: String
    /// 10 段增益（dB，±12 范围内）
    let gains: [Double]

    var localizedName: String {
        NSLocalizedString(nameKey, comment: "")
    }
}

enum BuiltinEQPresets {
    /// 10 段固定频点（Hz）
    static let bands10: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    /// 自定义 10 段滑杆编辑器的标记 key
    static let customKey = "custom"

    /// 7 个内置预设（含 flat）
    static let all: [BuiltinEQPreset] = [
        BuiltinEQPreset(key: "flat", nameKey: "preset_flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        BuiltinEQPreset(key: "pop", nameKey: "preset_pop", gains: [-1, 0, 1.5, 2.5, 3, 2.5, 1.5, 0, -0.5, -1]),
        BuiltinEQPreset(key: "rock", nameKey: "preset_rock", gains: [4, 3, 1.5, 0, -1, 0, 1.5, 3, 3.5, 4]),
        BuiltinEQPreset(key: "jazz", nameKey: "preset_jazz", gains: [3, 2, 1, 1, -0.5, -1, 0, 1, 2, 3]),
        BuiltinEQPreset(key: "classical", nameKey: "preset_classical", gains: [3, 2, 1, -0.5, -1, -1, -0.5, 1, 2, 3]),
        BuiltinEQPreset(key: "bass", nameKey: "preset_bass", gains: [6, 4.5, 3, 1.5, 0, 0, 0, 0, 0, 0]),
        BuiltinEQPreset(key: "vocal", nameKey: "preset_vocal", gains: [-1.5, -1, 0, 1, 2.5, 3.5, 3, 1.5, 0, -1]),
    ]

    static func preset(for key: String) -> BuiltinEQPreset? {
        all.first { $0.key == key }
    }

    /// 解析指定 key 对应的 10 段增益。
    /// - Parameters:
    ///   - key: 预设 key 或 BuiltinEQPresets.customKey
    ///   - storedCustomGains: custom 模式下的持久化增益（nil 表示无自定义数据）
    /// - Returns: 合法 10 段增益；未知 key / 自定义无数据时返回 nil
    static func gains(for key: String, storedCustomGains: [Double]? = nil) -> [Double]? {
        if key == customKey {
            return storedCustomGains
        }
        return preset(for: key)?.gains
    }
}
