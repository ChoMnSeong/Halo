import AppKit
import SwiftUI

/// 한 화면의 노치(또는 가상 노치) 치수.
struct NotchMetrics {
    var notchSize: CGSize
    var hasPhysicalNotch: Bool
}

enum ScreenGeometry {
    /// 시스템 주 디스플레이 = 전역 좌표 원점 (0,0) 에 있는 화면(메뉴막대 기본 위치).
    static var mainScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// 현재 마우스 포인터가 올라가 있는 화면.
    static var screenUnderMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) } ?? mainScreen
    }

    /// 물리 노치가 있는 화면들.
    static var notchedScreens: [NSScreen] {
        NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let top = screen.safeAreaInsets.top
        if top > 0 {
            // 물리 노치: 좌/우 보조영역(ears)의 폭을 빼서 노치 폭 산출.
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = screen.frame.width - left - right
            let w = width > 40 ? width : 200
            return NotchMetrics(notchSize: CGSize(width: w, height: top), hasPhysicalNotch: true)
        } else {
            // 노치 없는 디스플레이: 실제 메뉴막대 높이에 맞춘 가상 노치(statusThickness 22 가 아니라
            // 진짜 메뉴바 높이 — Tahoe 외부 30px — 라야 노치가 메뉴바를 끝까지 덮어 flush 해 보임).
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            let h = menuBar > 1 ? menuBar : max(NSStatusBar.system.thickness, 24)
            return NotchMetrics(notchSize: CGSize(width: 190, height: h), hasPhysicalNotch: false)
        }
    }

    /// 펼친 트레이(+설정)까지 담는 패널 전체 크기(고정). 투명 여백 + 그림자 포함.
    static func panelSize(for m: NotchMetrics) -> CGSize {
        // 좌우 각 36pt, 하단 48pt 투명 여백 — ambient 그림자(r22, y14)가 번지는 공간 확보.
        // open 시 PassthroughView 가 bounds 전체를 hit 하므로 무작정 키우지 않고 최소만.
        let w = max(m.notchSize.width, NotchLayout.trayWidth + 2 * NotchLayout.topFlare) + 72
        let h = m.notchSize.height - NotchLayout.trayOverlap + NotchLayout.maxTrayHeight + 48
        return CGSize(width: w, height: h)
    }

    static func panelFrame(for screen: NSScreen, size: CGSize) -> CGRect {
        let origin = CGPoint(x: screen.frame.midX - size.width / 2,
                             y: screen.frame.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}

/// 레이아웃 상수 (SwiftUI 뷰와 패널 크기 계산이 공유). 이름이 SwiftUI.Layout 과 겹치지 않도록 NotchLayout.
enum NotchLayout {
    static let trayWidth: CGFloat = 360
    static let tabChrome: CGFloat = 54      // 탭바 + 패딩 overhead(본문 위/아래)
    static let maxBodyHeight: CGFloat = 200 // 가장 큰 본문(설정/즐겨찾기). 패널은 탭별로 더 작게 줄어듦
    static var maxTrayHeight: CGFloat { maxBodyHeight + tabChrome }
    static let settingsBodyHeight: CGFloat = 200
    static let trayGap: CGFloat = 0         // 단일 실루엣 융합 — 노치/트레이 간격 제거
    static let trayOverlap: CGFloat = 8     // 트레이가 노치 바닥 아래로 파고드는 음의 겹침(seam 제거)
    static let notchBottomRadius: CGFloat = 13
    static let trayCornerRadius: CGFloat = 24  // 패널 하단 모서리(볼록)
    static let topFlare: CGFloat = 16          // 패널 상단 바깥 오목 플레어(화면 최상단으로 부드럽게 퍼짐)

    /// 밝은 벽지에서 그림자 접지감 실측 튜닝용.
    enum Tuning {
        static let ambientOpacity: CGFloat = 0.10  // 0.08~0.12 (밝은 벽지에서 약하면 ↑)
        static let ambientRadius: CGFloat = 22     // 20~24
    }
}

/// SwiftUI 가 읽는 화면별 노치 기하 모델(화면 변경/이동 시 컨트롤러가 갱신).
@MainActor
@Observable
final class NotchModel {
    var notchSize: CGSize
    var hasPhysicalNotch: Bool

    init(notchSize: CGSize, hasPhysicalNotch: Bool) {
        self.notchSize = notchSize
        self.hasPhysicalNotch = hasPhysicalNotch
    }
}

/// hitTest(메인 스레드, 비-actor 컨텍스트)에서 동기 접근하는 화면별 경량 상태 거울.
/// @Observable/@MainActor 격리와 무관하게 읽기 위한 plain 박스.
final class NotchHitState {
    var notchSize: CGSize
    /// 접힘 시 마우스를 받는 영역(기본=notchSize). 모듈이 노치 폭을 넘는 액세서리를 둘 때 넓힐 수 있음.
    var collapsedInteractiveSize: CGSize
    var isOpen = false

    init(notchSize: CGSize) {
        self.notchSize = notchSize
        self.collapsedInteractiveSize = notchSize
    }
}
