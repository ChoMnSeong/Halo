import AppKit
import ApplicationServices

/// 활성 수신 통화. acceptEl/declineEl 은 시스템 배너의 버튼(AXPress 대상).
struct CallEvent {
    let caller: String
    let acceptEl: AXUIElement?
    let declineEl: AXUIElement?
}

/// 일반 알림(통화 아님). lines = 배너에서 모은 텍스트(앱/제목/본문, 순서 가변).
struct NotificationEvent: Identifiable {
    let id = UUID()
    let lines: [String]
    let date: Date
    var title: String { lines.first ?? "알림" }
    var body: String { lines.dropFirst().joined(separator: "  ") }
}

/// 시스템 알림 배너(com.apple.notificationcenterui)를 접근성(AX)으로 관찰.
/// 모든 AX 호출은 권한 가드 뒤 + 실패는 조용히 흡수(없으면 무해). 통화만 1급 감지.
/// 비공개 AX 트리라 OS 버전 의존 → 절대경로/인덱스 금지, role/라벨 기반 재귀로 방어.
final class NotificationsMonitor {
    static let shared = NotificationsMonitor()

    private var observer: AXObserver?
    private var started = false
    private var ttlTimer: Timer?

    private(set) var current: CallEvent?
    /// 통화 변경 시 통지(메인 스레드에서 호출됨).
    var onChange: (() -> Void)?
    /// 일반 알림 도착 시 통지(메인 스레드).
    var onNotification: ((NotificationEvent) -> Void)?
    private var lastNotifLines: [String] = []
    private var lastNotifAt = Date.distantPast

    var isAuthorized: Bool { AXIsProcessTrusted() }

    // MARK: 시작

    func start() {
        guard !started, AXIsProcessTrusted() else { return }
        guard let nc = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }) else {
            NSLog("DL Notifications: notificationcenterui 프로세스 없음")
            return
        }
        let pid = nc.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)

        var obs: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &obs) == .success, let observer = obs else {
            NSLog("DL Notifications: AXObserverCreate 실패")
            return
        }
        self.observer = observer
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appEl, kAXWindowCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        started = true
        NSLog("DL Notifications: AX 관찰 시작 (pid \(pid))")
    }

    /// C 함수포인터(캡처 불가) → refcon 으로 self 전달.
    private static let callback: AXObserverCallback = { _, element, _, refcon in
        guard let refcon else { return }
        let me = Unmanaged<NotificationsMonitor>.fromOpaque(refcon).takeUnretainedValue()
        me.handleNewWindow(element)
    }

    private func handleNewWindow(_ window: AXUIElement) {
        parse(window)
        // SwiftUI lazy 렌더로 첫 파싱이 비어 올 수 있어 짧게 1회 재시도.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.parse(window) }
    }

    // MARK: 파싱

    private func parse(_ window: AXUIElement) {
        var texts: [String] = []
        var buttons: [(ident: String, label: String, el: AXUIElement)] = []
        walk(window, depth: 0, texts: &texts, buttons: &buttons)
        guard !texts.isEmpty || !buttons.isEmpty else { return }

        // 진단 로그(실제 배너 구조 확인용 — 매칭 보정에 사용).
        NSLog("DL banner: texts=\(texts.prefix(4)) buttons=\(buttons.map { "\($0.ident)|\($0.label)" })")

        if let accept = buttons.first(where: { matchAccept($0.label) }),
           let decline = buttons.first(where: { matchDecline($0.label) }) {
            // 통화 = 수락 라벨 버튼 + 거절 라벨 버튼 쌍(일반 알림엔 거절 라벨 없음).
            let caller = texts.first(where: { !$0.isEmpty }) ?? "수신 전화"
            setCurrent(CallEvent(caller: caller, acceptEl: accept.el, declineEl: decline.el))
        } else if !texts.isEmpty {
            // 일반 알림. parse 가 즉시+0.12s 두 번 도므로 같은 내용 dedup.
            let now = Date()
            if texts == lastNotifLines, now.timeIntervalSince(lastNotifAt) < 2 { return }
            lastNotifLines = texts
            lastNotifAt = now
            onNotification?(NotificationEvent(lines: texts, date: now))
        }
    }

    private func walk(_ el: AXUIElement, depth: Int,
                      texts: inout [String],
                      buttons: inout [(ident: String, label: String, el: AXUIElement)]) {
        if depth > 30 { return }
        switch strAttr(el, kAXRoleAttribute) {
        case "AXStaticText":
            if let v = strAttr(el, kAXValueAttribute) ?? strAttr(el, kAXDescriptionAttribute),
               !v.isEmpty { texts.append(v) }
        case "AXButton", "AXMenuButton":
            let label = strAttr(el, kAXTitleAttribute)
                ?? strAttr(el, kAXDescriptionAttribute)
                ?? strAttr(el, "AXAttributedDescription") ?? ""
            let ident = strAttr(el, kAXIdentifierAttribute) ?? ""
            buttons.append((ident, label, el))
        default:
            break
        }
        if let children = childrenAttr(el) {
            for child in children { walk(child, depth: depth + 1, texts: &texts, buttons: &buttons) }
        }
    }

    private func strAttr(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        if let s = ref as? String { return s }
        if let a = ref as? NSAttributedString { return a.string }
        return nil
    }

    private func childrenAttr(_ el: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success else { return nil }
        return ref as? [AXUIElement]
    }

    // 다국어 + 라벨 기반(인덱스/비현지화 generic identifier 의존 금지 — 오탐 방지).
    private func matchAccept(_ label: String) -> Bool {
        label.range(of: "accept|answer|join|수락|응답|받기|참가", options: [.regularExpression, .caseInsensitive]) != nil
    }
    private func matchDecline(_ label: String) -> Bool {
        label.range(of: "decline|reject|거절|거부", options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: 상태

    private func setCurrent(_ ev: CallEvent?) {
        current = ev
        onChange?()
        ttlTimer?.invalidate()
        if ev != nil {
            // 종료 알림 누락 폴백 — 40초 후 강제 해제(노치가 펼친 채 멈추지 않게).
            ttlTimer = Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { [weak self] _ in
                self?.setCurrent(nil)
            }
        }
    }

    func accept() {
        if let el = current?.acceptEl { AXUIElementPerformAction(el, kAXPressAction as CFString) }
        setCurrent(nil)
    }
    func decline() {
        if let el = current?.declineEl { AXUIElementPerformAction(el, kAXPressAction as CFString) }
        setCurrent(nil)
    }
}
