import SwiftUI
import AppKit
import ApplicationServices

/// 모듈 — 수신 통화(FaceTime/연속성). 접근성 권한으로 시스템 통화 배너를 감지.
/// 권한 없거나 감지 실패면 .idle 로 조용히 흡수(셸프/즐겨찾기 무영향).
@MainActor
@Observable
final class CallsModule: NotchModule {
    static let shared = CallsModule()

    let id = "calls"
    let title = "통화"
    let symbol = "phone.fill"
    let tabOrder = 5

    var permission: ModulePermission { .accessibility }

    private(set) var isAuthorized = AXIsProcessTrusted()
    private(set) var incoming: CallEvent?
    private var pollTimer: Timer?

    /// 수신 중이면 노치 점령(.event) + 자동 펼침.
    var activation: ModuleActivation { incoming != nil ? .event : .idle }
    var wantsAutoExpand: Bool { incoming != nil }
    var preferredExpandedHeight: CGFloat {
        if !isAuthorized { return 124 }
        return incoming != nil ? 112 : 84
    }

    func onBootstrap() {
        NotificationsMonitor.shared.onChange = { [weak self] in
            Task { @MainActor in self?.incoming = NotificationsMonitor.shared.current }
        }
        if isAuthorized { NotificationsMonitor.shared.start() }
        // 권한 회복 폴링(설정에서 켜고 돌아오면 앱 재시작 없이 자동 시작).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = AXIsProcessTrusted()
                if now != self.isAuthorized {
                    self.isAuthorized = now
                    if now { NotificationsMonitor.shared.start() }
                }
            }
        }
    }

    func expandedView() -> AnyView { AnyView(CallsTabBody()) }

    func collapsedLeading() -> AnyView? {
        guard incoming != nil else { return nil }
        return AnyView(Image(systemName: "phone.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.green))
    }
    func collapsedTrailing() -> AnyView? {
        guard let c = incoming else { return nil }
        return AnyView(Text(c.caller).font(.system(size: 11, weight: .semibold)).foregroundStyle(.green).lineLimit(1))
    }

    /// 접근성 권한 요청(시스템 프롬프트 + 설정 창).
    func requestPermission() {
        // 프롬프트 옵션으로 호출하면 앱이 접근성 목록에 등록되고 다이얼로그가 뜸.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func accept() { NotificationsMonitor.shared.accept() }
    func decline() { NotificationsMonitor.shared.decline() }
}

/// 통화 탭 본문 — 권한 카드 / 빈 상태 / 수신 통화 카드(받기·거절).
struct CallsTabBody: View {
    private var module = CallsModule.shared

    var body: some View {
        Group {
            if !module.isAuthorized {
                permissionCard
            } else if let c = module.incoming {
                callCard(c)
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionCard: some View {
        VStack(spacing: 7) {
            Image(systemName: "phone.badge.waveform")
                .font(.system(size: 19)).foregroundStyle(.white.opacity(0.5))
            Text("수신 전화를 노치에 표시하려면\n손쉬운 사용(접근성) 권한이 필요합니다")
                .font(.system(size: 10.5)).multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
            Button { module.requestPermission() } label: {
                Text("권한 허용 · 설정 열기")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.14)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func callCard(_ c: CallEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill").font(.system(size: 20)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.caller).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                Text("수신 전화").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button { module.decline() } label: {
                Image(systemName: "phone.down.fill").font(.system(size: 14))
                    .foregroundStyle(.white).frame(width: 34, height: 34)
                    .background(Circle().fill(.red))
            }
            .buttonStyle(.plain)
            Button { module.accept() } label: {
                Image(systemName: "phone.fill").font(.system(size: 14))
                    .foregroundStyle(.white).frame(width: 34, height: 34)
                    .background(Circle().fill(.green))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleView: some View {
        VStack(spacing: 6) {
            Image(systemName: "phone")
                .font(.system(size: 19)).foregroundStyle(.white.opacity(0.4))
            Text("수신 전화가 여기 표시됩니다")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
