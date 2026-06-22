import SwiftUI
import AppKit

/// 바닥 두 모서리가 둥근 노치 모양. NotchHead(접힘/오버레이)가 사용.
struct NotchShape: Shape {
    var bottomRadius: CGFloat = NotchLayout.notchBottomRadius

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height, rect.width / 2)
        return Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// 노치 머리(평범) — 순수 .black. 활동 없을 때 접힘 상태 + 펼침 시 최상단 black 보장.
struct NotchHead: View {
    var body: some View {
        NotchShape()
            .fill(.black)
            .contentShape(NotchShape())
    }
}

/// 접힘 라이브 액티비티 — 노치 좌우(ear)로 펼쳐지는 검은 알약. 왼쪽/오른쪽 콘텐츠가 노치를 감싼다.
/// 폭 = notchWidth + 2*ear, 패널 중앙 정렬이라 가운데 노치-갭이 화면 중앙(=물리 노치)에 맞음.
struct CollapsedBar: View {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let leading: AnyView?
    let trailing: AnyView?

    static let ear: CGFloat = 62

    var body: some View {
        ZStack {
            NotchShape(bottomRadius: NotchLayout.notchBottomRadius).fill(.black)
            HStack(spacing: 0) {
                (leading ?? AnyView(EmptyView()))
                    .frame(width: Self.ear - 8, alignment: .trailing)
                    .padding(.trailing, 8)
                Color.clear.frame(width: notchWidth)
                (trailing ?? AnyView(EmptyView()))
                    .frame(width: Self.ear - 8, alignment: .leading)
                    .padding(.leading, 8)
            }
        }
        .frame(width: notchWidth + 2 * Self.ear, height: notchHeight)
    }
}

/// 펼침 패널 = 화면 최상단에서 그대로 내려오는 단일 검은 패널(노치와 한 몸).
/// 상단 모서리는 바깥으로 부드럽게 퍼지는 **오목 플레어**(화면 최상단에 붙음), 하단은 볼록 라운드.
/// rect 폭 = trayWidth + 2*topFlare. 본문(콘텐츠) 폭 = trayWidth(좌우 topFlare 안쪽).
struct ExpandedPanelShape: Shape {
    var topFlare: CGFloat = NotchLayout.topFlare
    var bottomRadius: CGFloat = NotchLayout.trayCornerRadius

    func path(in rect: CGRect) -> Path {
        let tf = max(0, topFlare)
        let lx = rect.minX + tf            // 본문 좌측면
        let rx = rect.maxX - tf            // 본문 우측면
        let br = max(0, min(bottomRadius, (rx - lx) / 2, rect.height / 2))

        return Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))            // 좌상단(화면 최상단, 바깥)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))         // 상단 변(풀폭)
            // 우상단 오목 플레어: 상단 변 → 본문 우측면으로 부드럽게(바깥→안)
            p.addQuadCurve(to: CGPoint(x: rx, y: rect.minY + tf),
                           control: CGPoint(x: rx, y: rect.minY))
            p.addLine(to: CGPoint(x: rx, y: rect.maxY - br))           // 우측면
            p.addQuadCurve(to: CGPoint(x: rx - br, y: rect.maxY),      // 우하단 볼록
                           control: CGPoint(x: rx, y: rect.maxY))
            p.addLine(to: CGPoint(x: lx + br, y: rect.maxY))           // 하단 변
            p.addQuadCurve(to: CGPoint(x: lx, y: rect.maxY - br),      // 좌하단 볼록
                           control: CGPoint(x: lx, y: rect.maxY))
            p.addLine(to: CGPoint(x: lx, y: rect.minY + tf))           // 좌측면
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),    // 좌상단 오목 플레어
                           control: CGPoint(x: lx, y: rect.minY))
            p.closeSubpath()
        }
    }
}

/// 단일 패널 배경 = fill(그라데이션) + 상단 highlight + 이중 rim + 3겹 접지 그림자.
struct TrayBackground: View {
    let dropping: Bool
    private var shape: ExpandedPanelShape { ExpandedPanelShape() }

    var body: some View {
        shape
            .fill(LinearGradient(
                colors: [Color.black.opacity(0.98), Color.black.opacity(0.95)],
                startPoint: .top, endPoint: .bottom))
            .overlay(                                           // (a) 상단 inner highlight(유리 질감)
                LinearGradient(colors: [.white.opacity(0.06), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(shape)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false))
            .overlay(                                           // (b) 안쪽 흰 rim / 드롭 시 accent
                shape.stroke(dropping ? Color.accentColor : Color.white.opacity(0.08),
                             lineWidth: dropping ? 2 : 1))
            .background(                                        // (c) 바깥 어두운 정의선(접지)
                shape.stroke(Color.black.opacity(0.35), lineWidth: 0.75))
            .compositingGroup()
            .shadow(color: .black.opacity(NotchLayout.Tuning.ambientOpacity),
                    radius: NotchLayout.Tuning.ambientRadius, y: 14)   // ambient(넓고 옅게)
            .shadow(color: .black.opacity(0.13), radius: 9, y: 5)       // mid(형태 분리)
            .shadow(color: .black.opacity(0.20), radius: 3, y: 2)       // contact(접지선)
    }
}

/// 노치 오버레이 루트(화면별 model/hitState 주입). 셸은 실루엣/투과/상태머신만, 콘텐츠는 모듈.
struct NotchContentView: View {
    let model: NotchModel
    let hitState: NotchHitState

    @State private var hovering = false
    @State private var dropping = false
    @State private var selectedTab = ShelfModule.shared.id

    private var store = ShelfStore.shared
    private var settings = AppSettings.shared
    private var registry = ModuleRegistry.shared

    init(model: NotchModel, hitState: NotchHitState) {
        self.model = model
        self.hitState = hitState
    }

    private var isOpen: Bool {
        hovering || dropping || settings.isPinned || registry.wantsAutoExpand
    }

    /// 현재 선택 탭의 본문 높이(패널이 내용에 맞게 줄어듦).
    private var currentBodyHeight: CGFloat {
        if selectedTab == kSettingsTab { return NotchLayout.settingsBodyHeight }
        let m = registry.tabModules.first { $0.id == selectedTab } ?? registry.tabModules.first
        return m?.preferredExpandedHeight ?? NotchLayout.maxBodyHeight
    }

    var body: some View {
        let bodyHeight = currentBodyHeight
        let totalHeight = model.notchSize.height + bodyHeight + NotchLayout.tabChrome
        let panelWidth = NotchLayout.trayWidth + 2 * NotchLayout.topFlare   // 본문 폭 = trayWidth(좌우 플레어 안쪽)

        // 접힘 시 노치를 점령한 모듈의 ear/peek 콘텐츠.
        let focus = registry.focusModule
        let lead = focus.flatMap { $0.collapsedLeading() }
        let trail = focus.flatMap { $0.collapsedTrailing() }
        let peek = focus.flatMap { $0.collapsedPeek() }
        let hasEars = (lead != nil || trail != nil) && peek == nil

        ZStack(alignment: .top) {
            // 드롭다운 패널 레이어: 펼침(탭 트레이) 또는 접힘 peek(카드).
            if isOpen {
                ZStack(alignment: .top) {
                    TrayBackground(dropping: dropping)   // 셰이프+그림자(클립 안 함 → 그림자 보존)

                    ModuleTray(selectedTab: $selectedTab, dropping: dropping, bodyHeight: bodyHeight)
                        .padding(.top, model.notchSize.height)   // 노치/메뉴바 영역 아래부터
                        .frame(width: panelWidth, height: totalHeight, alignment: .top)
                        .clipShape(ExpandedPanelShape())          // 콘텐츠만 패널 안으로 클립
                }
                .frame(width: panelWidth, height: totalHeight, alignment: .top)
                .contentShape(ExpandedPanelShape())   // 패널 바깥 투과
                .animation(.spring(response: 0.3, dampingFraction: 0.86), value: totalHeight)
                .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            } else if let peek {
                let peekH = NotchLayout.peekHeight
                let peekTotal = model.notchSize.height + peekH
                ZStack(alignment: .top) {
                    TrayBackground(dropping: false)
                    peek
                        .frame(width: NotchLayout.trayWidth, height: peekH)
                        .padding(.top, model.notchSize.height)
                        .frame(width: panelWidth, height: peekTotal, alignment: .top)
                        .clipShape(ExpandedPanelShape())
                }
                .frame(width: panelWidth, height: peekTotal, alignment: .top)
                .contentShape(ExpandedPanelShape())
                .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }

            // 노치 인디케이터: ear 알약(라이브 액티비티) 또는 평범한 노치.
            if !isOpen && hasEars {
                CollapsedBar(notchWidth: model.notchSize.width,
                             notchHeight: model.notchSize.height,
                             leading: lead, trailing: trail)
            } else {
                NotchHead()
                    .frame(width: model.notchSize.width, height: model.notchSize.height)
            }
        }
        .onHover { hovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            // 활성 탭으로 라우팅: 즐겨찾기 탭이 열려 있으면 즐겨찾기, 그 외(노치/셸프 탭)엔 셸프.
            if selectedTab == FavoritesModule.shared.id {
                FavoritesStore.shared.add(urls: urls)
            } else {
                store.add(urls: urls)
            }
            return true
        } isTargeted: { dropping = $0 }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isOpen)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: hasEars)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: peek != nil)
        .onChange(of: isOpen) { _, newValue in hitState.isOpen = newValue }
        .onChange(of: hasEars) { _, has in updateCollapsedHit(has) }
        .onAppear { hitState.isOpen = isOpen; updateCollapsedHit(hasEars) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all)   // 노치 화면 safe area 인셋 무시 → 패널이 화면 최상단에 붙음
    }

    /// 접힘 시 마우스 받는 영역: ear 펼침이면 알약 폭, 아니면 노치 폭.
    private func updateCollapsedHit(_ hasEars: Bool) {
        hitState.collapsedInteractiveSize = hasEars
            ? CGSize(width: model.notchSize.width + 2 * CollapsedBar.ear, height: model.notchSize.height)
            : model.notchSize
    }
}

/// 펼침 트레이 — 탭바(모듈들 + 설정) + 선택 탭 본문. 배경/그림자는 TrayBackground 전담.
struct ModuleTray: View {
    @Binding var selectedTab: String
    let dropping: Bool
    let bodyHeight: CGFloat
    private var registry = ModuleRegistry.shared

    init(selectedTab: Binding<String>, dropping: Bool, bodyHeight: CGFloat) {
        self._selectedTab = selectedTab
        self.dropping = dropping
        self.bodyHeight = bodyHeight
    }

    var body: some View {
        VStack(spacing: 8) {
            tabBar
            content
                .frame(maxWidth: .infinity, minHeight: bodyHeight, maxHeight: bodyHeight)   // 탭별 본문 높이(패널이 줄어듦)
        }
        .padding(12)
        .frame(width: NotchLayout.trayWidth)
    }

    @ViewBuilder private var content: some View {
        if selectedTab == kSettingsTab {
            SettingsPage()
        } else if let m = registry.tabModules.first(where: { $0.id == selectedTab }) {
            m.expandedView()
        } else if let first = registry.tabModules.first {
            first.expandedView()
        } else {
            EmptyShelfHint()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(registry.tabModules, id: \.id) { m in
                        tabButton(id: m.id, symbol: m.symbol, label: m.title)
                    }
                }
            }
            tabButton(id: kSettingsTab, symbol: "gearshape.fill", label: "설정")   // 우측 고정
        }
    }

    private func tabButton(id: String, symbol: String, label: String) -> some View {
        let active = selectedTab == id
        return Button { selectedTab = id } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                if active { Text(label).font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(active ? AnyShapeStyle(.white.opacity(0.95)) : AnyShapeStyle(.white.opacity(0.45)))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(active ? Color.white.opacity(0.12) : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 노치 안 톱니바퀴에서 여는 설정 페이지.
struct SettingsPage: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("표시 화면")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))

                ForEach(DisplayMode.allCases) { mode in
                    Button { settings.displayMode = mode } label: {
                        HStack(spacing: 8) {
                            Image(systemName: settings.displayMode == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(settings.displayMode == mode ? Color.accentColor : .white.opacity(0.35))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text(mode.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(.white.opacity(0.12))

                settingsToggle("전체화면에서 숨기기", isOn: $settings.hideInFullScreen)
                settingsToggle("항상 펼치기", isOn: $settings.isPinned)
                settingsToggle("로그인 시 실행", isOn: $settings.launchAtLogin)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.accentColor)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.8))
    }
}

struct EmptyShelfHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.4))
            Text("여기로 파일을 드래그하세요")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 셸프 파일 칩 — 썸네일 + 이름, 드래그로 꺼내기/우클릭 메뉴/호버 제거.
struct ShelfChip: View {
    let item: ShelfItem
    @State private var thumb: NSImage?
    @State private var hover = false
    private var store = ShelfStore.shared

    init(item: ShelfItem) { self.item = item }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "doc")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(14)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.07)))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if hover {
                    Button { store.remove(item) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }

            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .onHover { hover = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Finder에서 보기") { store.reveal(item) }
            Button("제거", role: .destructive) { store.remove(item) }
        }
        .task(id: item.id) {
            thumb = await Thumbnailer.thumbnail(for: item.url, size: CGSize(width: 56, height: 56))
        }
    }
}
