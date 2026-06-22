import SwiftUI
import AppKit
import ApplicationServices

/// 모듈 — 일반 알림(메일/메시지/Slack 등). 도착 시 노치에 잠깐 피크 + 알림 탭에 피드.
/// 통화와 같은 NotificationsMonitor(접근성 AX) 단일 소스를 공유. 권한 없으면 .idle.
@MainActor
@Observable
final class NotificationsModule: NotchModule {
    static let shared = NotificationsModule()

    let id = "notifications"
    let title = "알림"
    let symbol = "bell.fill"
    let tabOrder = 7

    var permission: ModulePermission { .accessibility }

    private(set) var isAuthorized = AXIsProcessTrusted()
    private(set) var recent: [NotificationEvent] = []
    private(set) var peeking: NotificationEvent?     // 방금 도착(노치 피크)
    private var peekGen = 0
    private var pollTimer: Timer?

    /// 막 도착했을 때만 노치 잠깐 점령(.event). 평소엔 .idle(거슬리지 않게). 자동 펼침은 안 함.
    var activation: ModuleActivation { peeking != nil ? .event : .idle }
    var wantsAutoExpand: Bool { false }
    var preferredExpandedHeight: CGFloat {
        if !isAuthorized { return 124 }
        return recent.isEmpty ? 80 : 196
    }

    func onBootstrap() {
        NotificationsMonitor.shared.onNotification = { [weak self] ev in
            Task { @MainActor in self?.handle(ev) }
        }
        if isAuthorized { NotificationsMonitor.shared.start() }   // 멱등(이미 시작됐으면 무시)
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

    private func handle(_ ev: NotificationEvent) {
        recent.insert(ev, at: 0)
        if recent.count > 20 { recent.removeLast(recent.count - 20) }
        peeking = ev
        peekGen += 1
        let gen = peekGen
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.peekGen == gen else { return }
            self.peeking = nil
        }
    }

    func clearAll() { recent.removeAll() }
    func requestPermission() { CallsModule.shared.requestPermission() }

    func expandedView() -> AnyView { AnyView(NotificationsTabBody()) }

    func collapsedLeading() -> AnyView? {
        guard peeking != nil else { return nil }
        return AnyView(Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.9)))
    }
    func collapsedTrailing() -> AnyView? {
        guard let p = peeking else { return nil }
        return AnyView(Text(p.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1))
    }
}

/// 알림 탭 본문 — 권한 카드 / 빈 상태 / 최근 알림 피드.
struct NotificationsTabBody: View {
    private var module = NotificationsModule.shared

    var body: some View {
        Group {
            if !module.isAuthorized {
                permissionCard
            } else if module.recent.isEmpty {
                idleView
            } else {
                feed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feed: some View {
        VStack(spacing: 4) {
            HStack {
                Text("최근 알림").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { module.clearAll() } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.55)).help("지우기")
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(module.recent) { ev in NotificationRow(event: ev) }
                }
            }
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 7) {
            Image(systemName: "bell.badge")
                .font(.system(size: 19)).foregroundStyle(.white.opacity(0.5))
            Text("알림을 노치에 표시하려면\n손쉬운 사용(접근성) 권한이 필요합니다")
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

    private var idleView: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell")
                .font(.system(size: 19)).foregroundStyle(.white.opacity(0.4))
            Text("새 알림이 여기 모입니다")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotificationRow: View {
    let event: NotificationEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bell.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if !event.body.isEmpty {
                    Text(event.body)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
    }
}
