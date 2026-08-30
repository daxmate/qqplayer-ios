import AVKit
import SwiftUI

/// AVRoutePickerView 的 UIViewRepresentable 宿主。
/// 背景：离屏创建的 AVRoutePickerView 未加入 window 层级时 subviews 为空，
/// 找不到内部 UIButton → AirPlay 弹窗静默失效。常驻进 PlayerView 层级后内部
/// 按钮随布局加载完成，showAirPlayPicker() 即可程序化触发。
/// 视觉上完全隐藏（透明 + 不响应点击），仅作触发宿主。
struct RoutePickerHost: UIViewRepresentable {
    let onResolve: (AVRoutePickerView) -> Void

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.alpha = 0.01
        // 延迟到下一 runloop 回调：避免在视图更新期间修改 @State
        Task { @MainActor in
            onResolve(picker)
        }
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// 通过 responder 链解析宿主 UIViewController.view（fullScreenCover 的 hosting view）。
/// 封面下拉移动直接驱动该 view 的 UIKit transform——绕过 SwiftUI 状态重算/布局，
/// 避免 PlayerView 大视图树在拖动手势中每帧重算导致的掉帧抖动。
struct HostingViewAccessor: UIViewRepresentable {
    let onResolve: (UIView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var resolved = false
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard !context.coordinator.resolved else { return }
        var responder: UIResponder? = uiView
        while let r = responder {
            if let vc = r as? UIViewController {
                context.coordinator.resolved = true
                onResolve(vc.view)
                return
            }
            responder = r.next
        }
    }
}
