//  QQPlayerMacApp.swift
//  QQPlayer
//
//  macOS app entry point (QQPlayerMac target only). The iOS app uses
//  QQPlayerApp.swift as its @main; this file must stay out of the iOS
//  QQPlayer target to avoid duplicate @main declarations.
//
import SwiftUI

@main
struct QQPlayerMacApp: App {
    var body: some Scene {
        WindowGroup {
            Text("QQPlayer macOS")
                .frame(minWidth: 800, minHeight: 600)
        }
    }
}
