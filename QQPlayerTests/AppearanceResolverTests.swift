@testable import QQPlayer
import Testing
import UIKit

/// AppearanceResolver：forceDarkMode → UIUserInterfaceStyle 决策纯逻辑测试。
/// 防止回归到 SwiftUI preferredColorScheme(nil) 恢复失效的实现。
struct AppearanceResolverTests {
    @Test func forceDarkTrueMapsToDark() {
        #expect(AppearanceResolver.interfaceStyle(forceDark: true) == .dark)
    }

    @Test func forceDarkFalseMapsToUnspecified() {
        #expect(AppearanceResolver.interfaceStyle(forceDark: false) == .unspecified)
    }
}
