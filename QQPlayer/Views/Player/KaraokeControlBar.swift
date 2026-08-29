//
//  KaraokeControlBar.swift
//  QQPlayer
//
//  跟唱模式底部控制条：倍速 / 单句循环 / AB 循环（对齐桌面 ControlBar 语义）
//

import SwiftUI

/// 跟唱模式控制条（桌面 ControlBar 的 iOS 版）：三按钮横排胶囊。
/// - 倍速：点击循环档位（0.5x → … → 1.0x），非 1.0 高亮
/// - 单句循环：点击切换，开启高亮
/// - AB 循环：长按 0.5s 以当前句为 A（等选终点态显示 "AB…" + 提示）；已启用时单击退出
/// 状态全部读自 KaraokeController.shared（本组件只消费，不做决策）。
struct KaraokeControlBar: View {
    @ObservedObject private var karaoke = KaraokeController.shared
    @ObservedObject private var progress = PlayerEngine.shared.progress
    let accentColor: Color

    /// 当前句 index（长按 AB 取 A 点）；还没到第一句时为 nil
    private var currentLineIndex: Int? {
        LyricTiming.activeLineIndex(time: progress.playbackTime, in: karaoke.currentLines)
    }

    /// 等选终点态：AB 已启用但 b 未设（长按后、点歌词设终点前）
    private var isWaitingABEnd: Bool {
        guard let ab = karaoke.abLoop else { return false }
        return ab.b == nil
    }

    private var abLabel: String {
        isWaitingABEnd ? "AB…" : "AB"
    }

    var body: some View {
        VStack(spacing: 8) {
            if isWaitingABEnd {
                Text("点歌词设置 AB 终点")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
            }

            HStack(spacing: 10) {
                speedButton
                singleLineLoopButton
                abButton
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - 倍速

    private var speedButton: some View {
        Button {
            karaoke.cycleSpeed()
        } label: {
            pill(isHighlighted: karaoke.speed != 1.0) {
                Text(String(format: "%.1fx", karaoke.speed))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("倍速 \(String(format: "%.1f", karaoke.speed))")
    }

    // MARK: - 单句循环

    private var singleLineLoopButton: some View {
        Button {
            karaoke.toggleSingleLineLoop()
        } label: {
            pill(isHighlighted: karaoke.isSingleLineLoop) {
                Image(systemName: "repeat")
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("单句循环")
    }

    // MARK: - AB 循环

    /// AB 按钮：单击切换（用户 2026-08-29 拍板：不用长按）。
    /// 未启用 → 以当前句为 A 进入等选终点；已启用 → 退出 AB 循环。
    /// 等选终点态点击歌词行即设 B（clickLine 决策）。
    private var abButton: some View {
        Button {
            if karaoke.abLoop != nil {
                karaoke.exitABLoop()
            } else {
                guard let index = currentLineIndex else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                karaoke.enterABLoop(currentLine: index)
            }
        } label: {
            pill(isHighlighted: karaoke.abLoop != nil) {
                Text(abLabel)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("AB 循环")
        .accessibilityHint("单击以当前句为起点，点击歌词设置终点；再单击退出")
    }

    // MARK: - 胶囊样式

    private func pill<Content: View>(isHighlighted: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.footnote.weight(.semibold))
            .foregroundColor(isHighlighted ? accentColor : .primary.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().fill(isHighlighted ? accentColor.opacity(0.16) : Color.clear))
            .overlay(
                Capsule().stroke(
                    isHighlighted ? accentColor.opacity(0.7) : Color.primary.opacity(0.1),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    KaraokeControlBar(accentColor: .blue)
        .padding()
}
