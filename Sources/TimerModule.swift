import SwiftUI
import AppKit

/// 카운트다운 타이머 1개. 실행 중이면 endDate(절대 종료시각), 일시정지면 pausedRemaining.
struct TimerItem: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    let total: TimeInterval        // 원래 길이(링 비율용)
    var endDate: Date?             // 실행 중 종료시각(nil=일시정지)
    var pausedRemaining: TimeInterval?
    var finished: Bool

    func remaining(_ now: Date) -> TimeInterval {
        if let end = endDate { return max(0, end.timeIntervalSince(now)) }
        return pausedRemaining ?? 0
    }
    var isRunning: Bool { endDate != nil }
    func fraction(_ now: Date) -> Double {
        total > 0 ? min(1, max(0, remaining(now) / total)) : 0
    }
}

enum TimerPaths {
    static var indexFile: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicLake", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("timers.json")
    }
}

/// 타이머 스토어. 0.5초 틱으로 now 갱신(타이머 있을 때만) + 종료 감지/사운드. 절대 endDate 라 재실행에도 유지.
@MainActor
@Observable
final class TimerStore {
    static let shared = TimerStore()
    private(set) var items: [TimerItem] = []
    private(set) var now = Date()
    private var ticker: Timer?

    init() {
        load()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickNow() }
        }
    }

    private func tickNow() {
        guard !items.isEmpty else { return }   // 타이머 없으면 리렌더 안 함
        now = Date()
        var changed = false
        for i in items.indices where items[i].isRunning && !items[i].finished {
            if items[i].remaining(now) <= 0 {
                items[i].endDate = nil
                items[i].pausedRemaining = 0
                items[i].finished = true
                NSSound(named: "Glass")?.play()
                changed = true
            }
        }
        if changed { persist() }
    }

    func add(seconds: TimeInterval) {
        items.append(TimerItem(id: UUID(), label: "타이머", total: seconds,
                               endDate: Date().addingTimeInterval(seconds),
                               pausedRemaining: nil, finished: false))
        persist()
    }

    func togglePause(_ item: TimerItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        if items[i].finished { return }
        if let end = items[i].endDate {
            // 실행 중 → 일시정지
            items[i].pausedRemaining = max(0, end.timeIntervalSince(Date()))
            items[i].endDate = nil
        } else {
            // 일시정지 → 재개
            items[i].endDate = Date().addingTimeInterval(items[i].pausedRemaining ?? 0)
            items[i].pausedRemaining = nil
        }
        persist()
    }

    func remove(_ item: TimerItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    var hasRunning: Bool { items.contains { $0.isRunning } }
    var hasFinished: Bool { items.contains { $0.finished } }

    /// 노치에 보여줄 타이머: 가장 임박한 실행 중, 없으면 종료된 것.
    var primary: TimerItem? {
        items.filter { $0.isRunning }.min { $0.remaining(now) < $1.remaining(now) }
            ?? items.first { $0.finished }
    }

    func format(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    private func load() {
        guard let data = try? Data(contentsOf: TimerPaths.indexFile),
              let decoded = try? JSONDecoder().decode([TimerItem].self, from: data) else { return }
        items = decoded
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: TimerPaths.indexFile, options: .atomic)
    }
}

/// 모듈 — 타이머. 실행 중이면 노치에 링+남은시간(.live), 종료 시 .event(피크), 없으면 .idle.
@MainActor
@Observable
final class TimerModule: NotchModule {
    static let shared = TimerModule()

    let id = "timer"
    let title = "타이머"
    let symbol = "timer"
    let tabOrder = 3

    private var store = TimerStore.shared

    var activation: ModuleActivation {
        if store.hasFinished { return .event }
        if store.hasRunning { return .live }
        return store.items.isEmpty ? .idle : .passive
    }
    var preferredExpandedHeight: CGFloat {
        store.items.isEmpty ? 96 : min(CGFloat(62 + store.items.count * 42), 200)
    }

    func expandedView() -> AnyView { AnyView(TimerTabBody()) }
    func collapsedAccessory() -> AnyView { AnyView(TimerNotchAccessory()) }
}

/// 접힘 노치 슬롯 — 링 + 남은 시간(가장 임박한 타이머). "항상 보이게".
struct TimerNotchAccessory: View {
    private var store = TimerStore.shared

    var body: some View {
        if let t = store.primary {
            HStack(spacing: 4) {
                Circle()
                    .trim(from: 0, to: t.fraction(store.now))
                    .stroke(t.finished ? Color.red : Color.orange,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 10, height: 10)
                Text(t.finished ? "완료" : store.format(t.remaining(store.now)))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(t.finished ? .red : .orange)
            }
        }
    }
}

/// 타이머 탭 본문 — 프리셋 추가 + 타이머 목록.
struct TimerTabBody: View {
    private var store = TimerStore.shared
    private let presets: [(String, TimeInterval)] = [
        ("1분", 60), ("3분", 180), ("5분", 300), ("10분", 600), ("25분", 1500)
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(presets, id: \.0) { p in
                    Button { store.add(seconds: p.1) } label: {
                        Text("+\(p.0)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.1)))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 19)).foregroundStyle(.white.opacity(0.4))
                    Text("위에서 시간을 눌러 타이머 시작")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(store.items) { item in TimerRow(item: item) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TimerRow: View {
    let item: TimerItem
    private var store = TimerStore.shared

    init(item: TimerItem) { self.item = item }

    var body: some View {
        HStack(spacing: 8) {
            Button { store.togglePause(item) } label: {
                Image(systemName: item.finished ? "checkmark" : (item.isRunning ? "pause.fill" : "play.fill"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .disabled(item.finished)

            Button { store.remove(item) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)

            Text(item.label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))

            Spacer()

            Text(item.finished ? "완료" : store.format(item.remaining(store.now)))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(item.finished ? .red : .orange)
                .monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.05)))
    }
}
