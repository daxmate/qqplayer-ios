//
//  FormatInfoTests.swift
//  QQPlayerTests
//
//  格式识别：UI 显示格式（getFormatInfo）与音频引擎路由（canHandle）。
//  扩展名大小写不敏感；WAV/FLAC/MP3/M4A/AAC 走原生 AVAudioEngine，
//  其余（Opus/DSD/APE 等）走 SFBAudioEngine。
//

import Foundation
import Testing

@testable import QQPlayer

@MainActor
struct FormatInfoTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    // MARK: - getFormatInfo

    @Test("常见格式识别")
    func commonFormats() {
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.flac")).format == "FLAC")
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.mp3")).format == "MP3")
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.wav")).format == "WAV")
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.aac")).format == "AAC")
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.opus")).format == "Opus")
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.ogg")).format == "OGG")
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.dsf")).format == "DSD")
    }

    @Test("扩展名大小写不敏感")
    func caseInsensitiveExtension() {
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.FLAC")).format == "FLAC")
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.Mp3")).format == "MP3")
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.Opus")).format == "Opus")
    }

    @Test("Opus/OGG 格式带徽标")
    func opusBadge() {
        let opus = PlaybackRouter.getFormatInfo(for: url("/a.opus"))
        #expect(opus.badge == "OPUS")
        let ogg = PlaybackRouter.getFormatInfo(for: url("/a.ogg"))
        #expect(ogg.badge == "OGG")
    }

    @Test("无损格式无徽标")
    func noBadgeForLossless() {
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.flac")).badge == nil)
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.wav")).badge == nil)
        #expect(PlaybackRouter.getFormatInfo(for: url("/a.dsf")).badge == "DSD")
    }

    // MARK: - canHandle（引擎路由）

    @Test("原生格式走 AVAudioEngine（canHandle = false）")
    func nativeFormatsNotHandledBySFB() {
        for ext in ["wav", "flac", "mp3", "m4a", "aac"] {
            #expect(!SFBAudioEngineManager.canHandle(url: url("/a.\(ext)")), "\(ext) 应走原生引擎")
        }
    }

    @Test("高级格式走 SFBAudioEngine（canHandle = true）")
    func sfbFormatsHandled() {
        for ext in ["opus", "ogg", "dsf", "dff", "ape", "wv", "tta", "mka"] {
            #expect(SFBAudioEngineManager.canHandle(url: url("/a.\(ext)")), "\(ext) 应走 SFBAudioEngine")
        }
    }

    @Test("未知扩展名默认走 SFBAudioEngine")
    func unknownExtension() {
        #expect(SFBAudioEngineManager.canHandle(url: url("/a.xyz")))
    }

    @Test("无扩展名文件")
    func noExtension() {
        #expect(SFBAudioEngineManager.canHandle(url: url("/a")))
    }
}
