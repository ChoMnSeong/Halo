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
    private var peekTimer: Timer?

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
        peekTimer?.invalidate()
        peekTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.peekName = nil }
        }
    }

    func expandedView() -> AnyView { AnyView(ConnectTabBody()) }

    func collapsedAccessory() -> AnyView {
        AnyView(
            Group {
                if let n = peekName {
                    HStack(spacing: 4) {
                        Image(systemName: peekConnected ? "dot.radiowaves.left.and.right" : "wifi.slash")
                            .font(.system(size: 8, weight: .bold))
                        Text(n).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(peekConnected ? Color.blue : .white.opacity(0.6))
                }
            }
        )
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
