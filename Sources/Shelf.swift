import AppKit
import SwiftUI
import ServiceManagement
import QuickLookThumbnailing

/// 셸프 저장 위치. ~/Library/Application Support/DynamicLake/Shelf
enum ShelfPaths {
    static var dir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicLake/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static var indexFile: URL { dir.appendingPathComponent("index.json") }
}

/// 셸프 항목. 실제 파일은 dir 안에 보관 사본으로 존재.
struct ShelfItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String          // 원본 파일명(표시용)
    let storedFileName: String // 보관 사본 파일명(UUID 접두)
    let addedAt: Date

    var url: URL { ShelfPaths.dir.appendingPathComponent(storedFileName) }
}

/// 드롭된 파일을 보관·영속화하는 스토어.
@MainActor
@Observable
final class ShelfStore {
    static let shared = ShelfStore()
    private(set) var items: [ShelfItem] = []

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: ShelfPaths.indexFile),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        // 보관 파일이 사라진 항목은 정리.
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    /// 드롭한 URL 들을 보관 폴더로 복사하고 셸프에 추가(파일 I/O 는 백그라운드).
    func add(urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            var made: [ShelfItem] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let stored = ShelfStore.copyIntoShelf(url) {
                    made.append(ShelfItem(id: UUID(),
                                          name: url.lastPathComponent,
                                          storedFileName: stored,
                                          addedAt: Date()))
                }
            }
            let newItems = made
            await MainActor.run {
                self.items.insert(contentsOf: newItems, at: 0)
                self.persist()
            }
        }
    }

    func remove(_ item: ShelfItem) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        for item in items { try? FileManager.default.removeItem(at: item.url) }
        items.removeAll()
        persist()
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: ShelfPaths.indexFile, options: .atomic)
    }

    /// 보관 폴더로 파일 복사. 성공 시 보관 파일명 반환. (nonisolated — 백그라운드 호출용)
    nonisolated static func copyIntoShelf(_ src: URL) -> String? {
        let stored = "\(UUID().uuidString)-\(src.lastPathComponent)"
        let dest = ShelfPaths.dir.appendingPathComponent(stored)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return stored
        } catch {
            NSLog("DynamicLake 셸프 복사 실패: \(error.localizedDescription)")
            return nil
        }
    }
}

/// 노치 오버레이를 띄울 화면 모드.
enum DisplayMode: String, CaseIterable, Identifiable {
    case notchOnly       // 물리 노치가 있는 화면에만
    case followMouse     // 마우스가 있는 모니터로 따라다님
    case allMonitors     // 모든 화면 상단에 상시

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notchOnly:    return "노치 화면에서만"
        case .followMouse:  return "마우스 따라 표시"
        case .allMonitors:  return "모든 모니터"
        }
    }

    var detail: String {
        switch self {
        case .notchOnly:    return "물리 노치가 있는 화면에만"
        case .followMouse:  return "마우스가 있는 모니터로 따라다님"
        case .allMonitors:  return "모든 화면 상단에 상시 표시"
        }
    }
}

extension Notification.Name {
    /// 표시 화면 모드가 바뀌면 컨트롤러가 패널을 재구성하도록 알림.
    static let dlDisplayModeChanged = Notification.Name("dlDisplayModeChanged")
    /// 가시성 옵션(전체화면 숨기기 등)이 바뀌면 컨트롤러가 표시 여부를 갱신하도록 알림.
    static let dlVisibilityChanged = Notification.Name("dlVisibilityChanged")
}

/// 앱 설정(영속). 표시 화면 모드 / 전체화면 숨기기 / 항상 펼치기 / 로그인 시 실행.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var isPinned: Bool {
        didSet { UserDefaults.standard.set(isPinned, forKey: "isPinned") }
    }

    var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "displayMode")
            NotificationCenter.default.post(name: .dlDisplayModeChanged, object: nil)
        }
    }

    /// 전체화면 앱이 있는 화면에서는 노치 오버레이를 숨김.
    var hideInFullScreen: Bool {
        didSet {
            UserDefaults.standard.set(hideInFullScreen, forKey: "hideInFullScreen")
            NotificationCenter.default.post(name: .dlVisibilityChanged, object: nil)
        }
    }

    init() {
        isPinned = UserDefaults.standard.bool(forKey: "isPinned")
        displayMode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "")
            ?? .followMouse
        // 기본값 ON (없던 키면 true).
        hideInFullScreen = UserDefaults.standard.object(forKey: "hideInFullScreen") as? Bool ?? true
    }

    /// 로그인 항목(SMAppService). ad-hoc/Desktop 실행에선 비신뢰일 수 있어 /Applications 설치 권장.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("DynamicLake 로그인 항목 오류: \(error.localizedDescription)")
            }
        }
    }
}

/// QuickLook 썸네일(실패 시 파일 아이콘 폴백).
enum Thumbnailer {
    static func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: 2,
            representationTypes: .all
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return rep.nsImage
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
