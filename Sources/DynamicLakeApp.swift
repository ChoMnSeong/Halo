import SwiftUI
import AppKit

@main
struct DynamicLakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴막대(제어센터 옆) — 셸프 제어/설정/종료. 노치 오버레이는 AppDelegate 가 직접 관리.
        MenuBarExtra("Halo", systemImage: "tray.full.fill") {
            MenuBarContent()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 없는 백그라운드 앱 (LSUIElement 와 함께 이중 보장)
        NSApp.setActivationPolicy(.accessory)
        ModuleRegistry.shared.bootstrap()   // 모듈 등록(셸프 = 모듈 #1)
        notch = NotchController()
    }
}

/// 메뉴막대 드롭다운 메뉴.
struct MenuBarContent: View {
    @Bindable private var settings = AppSettings.shared
    private var store = ShelfStore.shared

    var body: some View {
        Text("Halo — 노치 유틸리티")

        Divider()

        Text(store.items.isEmpty ? "셸프 비어 있음" : "셸프 항목 \(store.items.count)개")

        Toggle("항상 펼치기", isOn: $settings.isPinned)

        Button("셸프 비우기") { store.clear() }
            .disabled(store.items.isEmpty)

        Toggle("로그인 시 실행", isOn: $settings.launchAtLogin)

        Divider()

        Button("종료") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
