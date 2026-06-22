import SwiftUI
import AppKit

/// 설정 탭 식별자(모듈이 아닌 고정 탭).
let kSettingsTab = "settings"

/// 접힘 상태에서 모듈이 노치를 점령하려는 강도(충돌 해소용). event > live > passive > idle.
enum ModuleActivation: Equatable, Comparable {
    case idle        // 표시할 것 없음
    case passive     // 잔잔한 상태(예: 셸프에 항목 있음)
    case live        // 지속 활동(재생 중, 통화 중, 충전 중)
    case event       // 방금 일어난 이벤트(트랙 변경, 충전 시작) — 잠깐 우선

    var rank: Int {
        switch self {
        case .idle:    return 0
        case .passive: return 1
        case .live:    return 2
        case .event:   return 3
        }
    }
    static func < (a: ModuleActivation, b: ModuleActivation) -> Bool { a.rank < b.rank }
}

/// 모듈이 요구하는 시스템 권한(향후 단계에서 사용).
enum ModulePermission {
    case none, mediaRemote, calendar, notifications, accessibility
}

/// 노치 기능 모듈. 셸(GrownShelf 실루엣·투과·다중화면·접힘펼침 상태머신)은 그대로 두고,
/// 모듈은 (a) 펼침 탭 본문 expandedView, (b) 접힘 시 노치 바닥 슬롯 collapsedAccessory 만 채운다.
@MainActor
protocol NotchModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }                 // 탭 아이콘(SF Symbol)
    var tabOrder: Int { get }                  // 펼침 탭 정적 순서(작을수록 앞)
    var permission: ModulePermission { get }
    var activation: ModuleActivation { get }   // 접힘 점령 강도(동적)
    var wantsAutoExpand: Bool { get }          // true 면 노치 자동 펼침(예: 전화 수신)
    var preferredExpandedHeight: CGFloat { get } // 펼침 본문 높이(패널이 내용에 맞게 줄어듦)
    func expandedView() -> AnyView             // 펼침 탭 본문
    func collapsedLeading() -> AnyView?        // 접힘 시 노치 왼쪽 ear(라이브 액티비티)
    func collapsedTrailing() -> AnyView?       // 접힘 시 노치 오른쪽 ear
    func collapsedPeek() -> AnyView?           // 접힘 시 노치 아래로 펼쳐지는 드롭다운 카드(ear 대신)
    func onBootstrap()                         // 등록 직후 1회(모니터 시작 등)
}

extension NotchModule {
    var permission: ModulePermission { .none }
    var wantsAutoExpand: Bool { false }
    var preferredExpandedHeight: CGFloat { 180 }
    func collapsedLeading() -> AnyView? { nil }
    func collapsedTrailing() -> AnyView? { nil }
    func collapsedPeek() -> AnyView? { nil }
    func onBootstrap() {}
}

/// 모듈 레지스트리. 화면 무관 단일 인스턴스(ShelfStore/AppSettings 의 .shared 패턴과 정합).
/// 다중패널은 model/hitState 만 화면별이고 모듈 상태는 공유 → 동기화 공짜.
@MainActor
@Observable
final class ModuleRegistry {
    static let shared = ModuleRegistry()
    private(set) var modules: [any NotchModule] = []

    func bootstrap() {
        guard modules.isEmpty else { return }
        register(ShelfModule.shared)
        register(TimerModule.shared)
        register(CallsModule.shared)
        register(NotificationsModule.shared)
        register(ConnectModule.shared)
        register(FavoritesModule.shared)
        // 이후 단계: register(NowPlayingModule.shared) …
        modules.forEach { $0.onBootstrap() }
    }

    func register(_ m: any NotchModule) {
        modules.append(m)
        modules.sort { $0.tabOrder < $1.tabOrder }
    }

    /// 펼침 탭 순서(정적).
    var tabModules: [any NotchModule] { modules }

    /// 접힘 상태에서 노치를 점령할 모듈(순수 선택: activation → tabOrder → id).
    var focusModule: (any NotchModule)? {
        modules
            .filter { $0.activation > .idle }
            .min { a, b in
                if a.activation != b.activation { return a.activation > b.activation } // 높은 activation 우선
                if a.tabOrder != b.tabOrder { return a.tabOrder < b.tabOrder }          // 낮은 tabOrder 우선
                return a.id < b.id
            }
    }

    /// 어떤 모듈이든 자동 펼침을 원하면 true(isOpen 식에 OR 합류).
    var wantsAutoExpand: Bool { modules.contains { $0.wantsAutoExpand } }
}

// ─────────────────────────────────────────────────────────────
// 모듈 #1 — 파일 셸프 (ShelfStore 무수정, 어댑터만 추가)
// ─────────────────────────────────────────────────────────────

@MainActor
@Observable
final class ShelfModule: NotchModule {
    static let shared = ShelfModule()

    let id = "shelf"
    let title = "셸프"
    let symbol = "tray.full.fill"
    let tabOrder = 0

    private var store = ShelfStore.shared

    /// 항목이 있으면 잔잔히(passive) 노치 바닥에 손잡이 표시.
    var activation: ModuleActivation { store.items.isEmpty ? .idle : .passive }

    /// 칩 한 줄(가로 스크롤) 높이만큼만. 비면 더 작게.
    var preferredExpandedHeight: CGFloat { store.items.isEmpty ? 64 : 104 }

    func expandedView() -> AnyView { AnyView(ShelfTabBody()) }
    // 셸프는 라이브 액티비티 아님 → ear 없음(접힘 시 평범한 노치).
}

/// 셸프 탭 본문 — 빈 상태 안내 또는 칩 가로 스크롤(+개수/비우기). 펼침 탭에 들어감.
struct ShelfTabBody: View {
    private var store = ShelfStore.shared

    var body: some View {
        VStack(spacing: 6) {
            if store.items.isEmpty {
                EmptyShelfHint()
            } else {
                HStack(spacing: 6) {
                    Text("\(store.items.count)개")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button { store.clear() } label: {
                        Image(systemName: "trash").font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.55))
                    .help("셸프 비우기")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.items) { item in ShelfChip(item: item) }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
