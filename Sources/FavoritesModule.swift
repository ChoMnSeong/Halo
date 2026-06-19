import SwiftUI
import AppKit

/// 즐겨찾기 항목 — 폴더/앱/파일의 원본 위치(셸프와 달리 사본 복사 안 함, 원본을 가리킴).
struct FavoriteItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: String

    var url: URL { URL(fileURLWithPath: path) }
}

enum FavoritesPaths {
    static var indexFile: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicLake", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("favorites.json")
    }
}

/// 즐겨찾기 스토어(영속). 원본 경로 참조.
@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()
    private(set) var items: [FavoriteItem] = []

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: FavoritesPaths.indexFile),
              let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data)
        else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(urls: [URL]) {
        var changed = false
        for url in urls {
            let path = url.path
            guard FileManager.default.fileExists(atPath: path),
                  !items.contains(where: { $0.path == path }) else { continue }
            items.append(FavoriteItem(id: UUID(), name: url.lastPathComponent, path: path))
            changed = true
        }
        if changed { persist() }
    }

    func remove(_ item: FavoriteItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func open(_ item: FavoriteItem) { NSWorkspace.shared.open(item.url) }
    func reveal(_ item: FavoriteItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: FavoritesPaths.indexFile, options: .atomic)
    }
}

/// 모듈 — 즐겨찾기 폴더/앱. 펼침 탭에 아이콘 그리드, 클릭하면 열림.
@MainActor
@Observable
final class FavoritesModule: NotchModule {
    static let shared = FavoritesModule()

    let id = "favorites"
    let title = "즐겨찾기"
    let symbol = "star.fill"
    let tabOrder = 10

    private var store = FavoritesStore.shared

    var activation: ModuleActivation { .idle }   // 접힘 노치 점령 안 함

    /// + 버튼줄 + 아이콘 그리드 행 수에 맞게(최대 200, 넘으면 스크롤).
    var preferredExpandedHeight: CGFloat {
        if store.items.isEmpty { return 96 }
        let cols = 4
        let rows = (store.items.count + cols - 1) / cols
        return min(CGFloat(34 + rows * 78), 200)
    }

    func expandedView() -> AnyView { AnyView(FavoritesTabBody()) }
}

/// 펼침 탭 본문 — 즐겨찾기 아이콘 그리드 + "+" 추가. 드래그 추가는 활성 탭 라우팅으로도 동작.
struct FavoritesTabBody: View {
    private var store = FavoritesStore.shared

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                Button { Self.pickAndAdd() } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .help("폴더/앱 추가")
            }

            if store.items.isEmpty {
                Button { Self.pickAndAdd() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "star")
                            .font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                        Text("폴더·앱을 끌어다 놓거나 + 로 추가")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 10)], spacing: 10) {
                        ForEach(store.items) { item in FavoriteChip(item: item) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 폴더/앱/파일 선택 창을 띄워 즐겨찾기에 추가(accessory 앱이라 먼저 활성화).
    static func pickAndAdd() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "추가"
        panel.message = "즐겨찾기에 추가할 폴더·앱·파일을 선택하세요"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            FavoritesStore.shared.add(urls: panel.urls)
        }
    }
}

/// 즐겨찾기 칩 — 파일 아이콘 + 이름, 클릭하면 열림, 호버 제거/우클릭.
struct FavoriteChip: View {
    let item: FavoriteItem
    @State private var hover = false
    private var store = FavoritesStore.shared

    init(item: FavoriteItem) { self.item = item }

    var body: some View {
        Button {
            store.open(item)
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .frame(width: 46, height: 46)
                Text(item.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 62)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { store.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -2)
            }
        }
        .onHover { hover = $0 }
        .contextMenu {
            Button("열기") { store.open(item) }
            Button("Finder에서 보기") { store.reveal(item) }
            Button("제거", role: .destructive) { store.remove(item) }
        }
    }
}
