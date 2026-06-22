import SwiftUI
import AppKit
import IOBluetooth

/// 블루투스 연결/해제 감지(IOBluetooth, classic 알림). 콜백은 메인 런루프.
final class BluetoothMonitor: NSObject {
    static let shared = BluetoothMonitor()

    var onConnect: ((String) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private(set) var connectedNames: [String] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        IOBluetoothDevice.register(forConnectNotifications: self,
                                   selector: #selector(deviceConnected(_:device:)))
        refresh()
        for d in pairedDevices where d.isConnected() {
            d.register(forDisconnectNotification: self,
                       selector: #selector(deviceDisconnected(_:device:)))
        }
    }

    private var pairedDevices: [IOBluetoothDevice] {
        IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "기기"
        device.register(forDisconnectNotification: self,
                        selector: #selector(deviceDisconnected(_:device:)))
        refresh()
        onConnect?(name)
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "기기"
        refresh()
        onDisconnect?(name)
    }

    private func refresh() {
        connectedNames = pairedDevices.filter { $0.isConnected() }.compactMap { $0.name }
    }
}

/// 모듈 — 블루투스 연결. 연결/해제 시 노치에 잠깐 피크 + 탭에 연결 기기 목록.
@MainActor
@Observable
final class ConnectModule: NotchModule {
    static let shared = ConnectModule()

    let id = "connect"
    let title = "연결"
    let symbol = "dot.radiowaves.left.and.right"
    let tabOrder = 8

    private(set) var peekName: String?
    private(set) var peekConnected = true
    private(set) var devices: [String] = []
    private var peekGen = 0

    var activation: ModuleActivation { peekName != nil ? .event : .idle }
    var preferredExpandedHeight: CGFloat {
        devices.isEmpty ? 80 : min(CGFloat(44 + devices.count * 32), 180)
    }

    func onBootstrap() {
        // IOBluetooth 콜백은 메인 스레드 보장 안 됨 → Task 로 메인 액터 호핑.
        BluetoothMonitor.shared.onConnect = { [weak self] name in
            Task { @MainActor in self?.peek(name, connected: true) }
        }
        BluetoothMonitor.shared.onDisconnect = { [weak self] name in
            Task { @MainActor in self?.peek(name, connected: false) }
        }
        BluetoothMonitor.shared.start()
        devices = BluetoothMonitor.shared.connectedNames
    }

    private func peek(_ name: String, connected: Bool) {
        peekName = name
        peekConnected = connected
        devices = BluetoothMonitor.shared.connectedNames
        // asyncAfter 는 런루프 모드와 무관하게 메인 큐에서 확실히 발화. 세대 카운터로 재트리거 시 옛 해제 무시.
        peekGen += 1
        let gen = peekGen
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.peekGen == gen else { return }
            self.peekName = nil
        }
    }

    func expandedView() -> AnyView { AnyView(ConnectTabBody()) }

    // 연결/해제 시 노치 아래로 펼쳐지는 드롭다운 카드(기기 아이콘 + 상태 + 이름).
    func collapsedPeek() -> AnyView? {
        guard let n = peekName else { return nil }
        return AnyView(
            HStack(spacing: 12) {
                Image(systemName: Self.icon(for: n))
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(peekConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(n)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    /// 기기 이름으로 아이콘 추정.
    static func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpod") || n.contains("buds") || n.contains("headphone")
            || n.contains("beats") || n.contains("wh-") || n.contains("sony") { return "headphones" }
        if n.contains("mouse") || n.contains("mx ") || n.contains("mx master")
            || n.contains("mx anywhere") || n.contains("magic mouse") { return "computermouse.fill" }
        if n.contains("keyboard") { return "keyboard.fill" }
        if n.contains("trackpad") { return "trackpad.fill" }
        return "dot.radiowaves.left.and.right"
    }
}

/// 연결 탭 본문 — 연결된 기기 목록.
struct ConnectTabBody: View {
    private var module = ConnectModule.shared

    var body: some View {
        Group {
            if module.devices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 19)).foregroundStyle(.white.opacity(0.4))
                    Text("연결된 블루투스 기기 없음")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(module.devices, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 12)).foregroundStyle(.blue)
                                Text(name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                                Spacer()
                                Text("연결됨").font(.system(size: 10)).foregroundStyle(.green)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
