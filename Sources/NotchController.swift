import AppKit
import SwiftUI

/// 노치 오버레이 패널. 비활성/투명/전 스페이스 공유, 메뉴막대 위 레벨.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar                // 메뉴막대(.mainMenu=24) 위
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                 // 그림자는 트레이가 SwiftUI 로 직접
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 투과 컨테이너: 접힘=노치 영역만, 펼침=전체만 마우스 이벤트를 받고
/// 나머지 투명 영역은 nil 반환으로 뒤 앱에 그대로 통과시킨다. (화면별 hitState 참조)
final class PassthroughView: NSView {
    private let hitState: NotchHitState

    init(frame: NSRect, hitState: NotchHitState) {
        self.hitState = hitState
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let interactive: NSRect
        if hitState.isOpen {
            interactive = bounds
        } else {
            let n = hitState.collapsedInteractiveSize
            interactive = NSRect(x: (bounds.width - n.width) / 2,
                                 y: bounds.height - n.height,
                                 width: n.width, height: n.height)
        }
        guard interactive.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// 표시 화면 모드에 따라 패널을 생성·배치하고 화면/마우스 변화를 추적.
@MainActor
final class NotchController {
    private final class PanelBox {
        let panel: NotchPanel
        let model: NotchModel
        let hitState: NotchHitState
        var screen: NSScreen
        init(panel: NotchPanel, model: NotchModel, hitState: NotchHitState, screen: NSScreen) {
            self.panel = panel
            self.model = model
            self.hitState = hitState
            self.screen = screen
        }
    }

    private var boxes: [PanelBox] = []
    private var mouseMonitor: Any?
    private var followFrame: CGRect?

    init() {
        rebuild()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(modeChanged),
                       name: .dlDisplayModeChanged, object: nil)
        nc.addObserver(self, selector: #selector(screensChanged),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(visibilityChanged),
                       name: .dlVisibilityChanged, object: nil)
        // 스페이스 전환(전체화면 진입/이탈 포함) 감지.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
    }

    // 모드 변경/화면 재구성은 다음 런루프로 미뤄 현재 이벤트(버튼 액션) 중 패널 파괴를 피한다.
    @objc private func modeChanged() {
        DispatchQueue.main.async { [weak self] in self?.rebuild() }
    }
    @objc private func screensChanged() {
        DispatchQueue.main.async { [weak self] in self?.rebuild() }
    }
    @objc private func visibilityChanged() {
        updateVisibility()
    }
    // 전체화면 창은 스페이스 전환 직후 곧바로 등록되지 않을 수 있어 약간 지연 후 갱신.
    @objc private func spaceChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.updateVisibility()
        }
    }

    private func rebuild() {
        teardown()
        let mode = AppSettings.shared.displayMode
        for screen in targetScreens(for: mode) {
            boxes.append(makeBox(for: screen))
        }
        if mode == .followMouse { startMouseMonitor() }
        updateVisibility()
    }

    private func teardown() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        for b in boxes { b.panel.orderOut(nil) }
        boxes.removeAll()
        followFrame = nil
    }

    private func targetScreens(for mode: DisplayMode) -> [NSScreen] {
        switch mode {
        case .notchOnly:
            let notched = ScreenGeometry.notchedScreens
            return notched.isEmpty ? [ScreenGeometry.mainScreen].compactMap { $0 } : notched
        case .allMonitors:
            return NSScreen.screens
        case .followMouse:
            return [ScreenGeometry.screenUnderMouse].compactMap { $0 }
        }
    }

    private func makeBox(for screen: NSScreen) -> PanelBox {
        let m = ScreenGeometry.metrics(for: screen)
        let model = NotchModel(notchSize: m.notchSize, hasPhysicalNotch: m.hasPhysicalNotch)
        let hitState = NotchHitState(notchSize: m.notchSize)

        let size = ScreenGeometry.panelSize(for: m)
        let frame = ScreenGeometry.panelFrame(for: screen, size: size)

        let panel = NotchPanel(contentRect: frame)
        let container = PassthroughView(frame: CGRect(origin: .zero, size: size), hitState: hitState)
        let hosting = NSHostingView(rootView: NotchContentView(model: model, hitState: hitState))
        hosting.safeAreaRegions = []   // 노치 화면 safe area 인셋 무시(패널이 화면 최상단에 붙도록)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        return PanelBox(panel: panel, model: model, hitState: hitState, screen: screen)
    }

    // MARK: 전체화면 숨기기

    /// 전체화면 앱이 있는 화면의 패널은 숨기고, 아니면 다시 표시.
    private func updateVisibility() {
        let hide = AppSettings.shared.hideInFullScreen
        for box in boxes {
            if hide && Self.isFullScreenPresent(on: box.screen) {
                box.panel.orderOut(nil)
            } else if !box.panel.isVisible {
                box.panel.orderFrontRegardless()
            }
        }
    }

    /// 해당 화면을 메뉴바까지 통째로 덮는 레이어0 창(=전체화면 앱)이 있는지.
    /// 최대화(메뉴바 아래에서 시작)와 구분하기 위해 화면 top 까지 덮는지로 판정.
    private static func isFullScreenPresent(on screen: NSScreen) -> Bool {
        guard let primaryH = ScreenGeometry.mainScreen?.frame.height else { return false }
        let f = screen.frame
        // bottom-left 전역 → CGWindowList 의 top-left 전역 사각형으로 변환.
        let target = CGRect(x: f.origin.x,
                            y: primaryH - (f.origin.y + f.height),
                            width: f.width, height: f.height)
        let ignore: Set<String> = [
            "Window Server", "Dock", "Wallpaper", "WallpaperAgent",
            "다이나믹레이크", "DynamicLake", "Control Center", "제어 센터", "Notification Center"
        ]
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if ignore.contains(owner) { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if r.width >= target.width - 2, r.height >= target.height - 2,
               abs(r.minX - target.minX) < 4, abs(r.minY - target.minY) < 4 {
                return true
            }
        }
        return false
    }

    // MARK: 마우스 따라 표시

    private func startMouseMonitor() {
        followFrame = ScreenGeometry.screenUnderMouse?.frame
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.followMouseTick()
        }
    }

    private func followMouseTick() {
        guard AppSettings.shared.displayMode == .followMouse,
              let box = boxes.first,
              let screen = ScreenGeometry.screenUnderMouse
        else { return }
        if screen.frame == followFrame { return }   // 같은 화면 → 무시
        if box.hitState.isOpen { return }            // 펼쳐진 중엔 안 옮김
        followFrame = screen.frame
        box.screen = screen

        let m = ScreenGeometry.metrics(for: screen)
        box.model.notchSize = m.notchSize
        box.model.hasPhysicalNotch = m.hasPhysicalNotch
        box.hitState.notchSize = m.notchSize
        box.hitState.collapsedInteractiveSize = m.notchSize

        let size = ScreenGeometry.panelSize(for: m)
        box.panel.setFrame(ScreenGeometry.panelFrame(for: screen, size: size), display: true)
        updateVisibility()   // 새 화면이 전체화면이면 숨김 처리
    }
}
