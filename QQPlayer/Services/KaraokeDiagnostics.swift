//
//  KaraokeDiagnostics.swift
//  QQPlayer
//
//  跟唱模式决策日志（2026-08-31 加，定位"跟唱模式下点击歌词选不中"）。
//
//  把点击歌词 → 跳转 → pending 判定 → 句末决策的完整链路追加写入
//  `Documents/karaoke-debug.log`（环形：超上限截断保留尾部），下次真机
//  复现后直接读沙盒文件即可拿到完整证据链，不需要实时抓 console。
//  问题定案后连同本文件一起删除。
//

import Foundation

enum KaraokeDiagnostics {
    private static let maxBytes = 200_000
    private static let keepTailBytes = 50_000

    private static var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static var logURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("karaoke-debug.log")
    }

    /// 追加一行日志（同步写，只在跟唱决策点低频调用，无性能顾虑）。
    static func log(_ message: String) {
        guard let url = logURL else { return }
        let line = "[\(timestamp)] \(message)\n"
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
                   size > maxBytes {
                    // 环形截断：保留尾部，避免文件无限增长
                    if let handle = try? FileHandle(forReadingFrom: url) {
                        defer { _ = try? handle.close() }
                        try? handle.seek(toOffset: UInt64(max(0, size - keepTailBytes)))
                        let tail = handle.readDataToEndOfFile()
                        _ = try? tail.write(to: url, options: .atomic)
                    }
                }
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { _ = try? handle.close() }
                    _ = try? handle.seekToEnd()
                    _ = try? handle.write(contentsOf: Data(line.utf8))
                    return
                }
            }
            try line.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // 诊断日志失败不影响播放
        }
    }
}
