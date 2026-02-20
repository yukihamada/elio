import Foundation
import CoreBluetooth
import MultipeerConnectivity
import SwiftUI
import UIKit

/// 近接デバイス自動発見・接続マネージャー
/// Bluetooth、Wi-Fi Direct、QRコードで自動接続
@MainActor
final class ProximityDiscoveryManager: NSObject, ObservableObject {
    static let shared = ProximityDiscoveryManager()

    // MARK: - Published Properties

    @Published var discoveredDevices: [ProximityDevice] = []
    @Published var isScanning = false
    @Published var autoConnectEnabled = true
    @Published var connectedDevices: Set<String> = []

    // MARK: - Bluetooth LE

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?

    // Service UUID for Elio P2P discovery
    private let serviceUUID = CBUUID(string: "E110-0000-0000-0000-0000-000000000001")
    private let characteristicUUID = CBUUID(string: "E110-0001-0000-0000-0000-000000000001")

    // MARK: - MultipeerConnectivity (Wi-Fi Direct)

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private let serviceType = "elio-p2p"
    private var peerID: MCPeerID!

    // MARK: - Trusted Devices

    @AppStorage("trustedDeviceIds") private var trustedDeviceIdsData: Data = Data()

    private var trustedDeviceIds: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: trustedDeviceIdsData)) ?? []
        }
        set {
            trustedDeviceIdsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        setupBluetooth()
        setupMultipeer()
    }

    // MARK: - Setup

    private func setupBluetooth() {
        centralManager = CBCentralManager(delegate: self, queue: .main)
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    private func setupMultipeer() {
        let deviceName = UIDevice.current.name
        peerID = MCPeerID(displayName: deviceName)

        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: [
            "deviceId": getDeviceId(),
            "hasLocalLLM": "\(hasLocalLLM())"
        ], serviceType: serviceType)
        advertiser?.delegate = self

        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
    }

    // MARK: - Discovery Control

    func startDiscovery() {
        guard !isScanning else { return }
        isScanning = true

        // Start Bluetooth scanning
        if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: [serviceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        }

        // Start advertising as peripheral
        if peripheralManager?.state == .poweredOn {
            startAdvertising()
        }

        // Start MultipeerConnectivity
        browser?.startBrowsingForPeers()
        advertiser?.startAdvertisingPeer()

        print("[Proximity] Started discovery (BLE + Multipeer)")
    }

    func stopDiscovery() {
        guard isScanning else { return }
        isScanning = false

        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()

        print("[Proximity] Stopped discovery")
    }

    private func startAdvertising() {
        let deviceIdData = getDeviceId().data(using: .utf8)!
        let characteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read],
            value: deviceIdData,
            permissions: [.readable]
        )

        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]

        peripheralManager?.add(service)
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: UIDevice.current.name
        ])
    }

    // MARK: - Connection Management

    func connect(to device: ProximityDevice) async throws {
        guard !connectedDevices.contains(device.id) else {
            print("[Proximity] Already connected to \(device.name)")
            return
        }

        switch device.connectionType {
        case .bluetooth:
            try await connectViaBluetooth(device)
        case .multipeer:
            try await connectViaMultipeer(device)
        case .qrCode:
            try await connectViaQRCode(device)
        }

        connectedDevices.insert(device.id)

        // Notify ChatModeManager
        await integrateWithP2P(device)
    }

    func disconnect(from deviceId: String) {
        connectedDevices.remove(deviceId)

        // Disconnect from MultipeerConnectivity
        if let session = session {
            let peer = session.connectedPeers.first(where: { $0.displayName.contains(deviceId) })
            if let peer = peer {
                session.disconnect()
            }
        }
    }

    private func connectViaBluetooth(_ device: ProximityDevice) async throws {
        // Bluetooth connection handled by centralManager didConnect callback
        print("[Proximity] Connecting via Bluetooth to \(device.name)")
    }

    private func connectViaMultipeer(_ device: ProximityDevice) async throws {
        // MultipeerConnectivity connection handled by browser foundPeer callback
        print("[Proximity] Connecting via Multipeer to \(device.name)")
    }

    private func connectViaQRCode(_ device: ProximityDevice) async throws {
        print("[Proximity] Connecting via QR Code to \(device.name)")
        // TODO: QR code connection requires building a P2PServer from the scanned URL
        // Currently discovery via Bonjour is the primary connection method
    }

    // MARK: - P2P Integration

    private func integrateWithP2P(_ device: ProximityDevice) async {
        // Register device with P2PBackend or PrivateServerManager
        print("[Proximity] Integrating \(device.name) with P2P mesh")
        // TODO: Bridge proximity-discovered devices into P2PBackend's available servers
        // Currently Bonjour discovery in P2PBackend handles server registration directly
    }

    // MARK: - Trust Management

    func trustDevice(_ deviceId: String) {
        var trusted = trustedDeviceIds
        trusted.insert(deviceId)
        trustedDeviceIds = trusted

        // Auto-connect if device is nearby
        if let device = discoveredDevices.first(where: { $0.id == deviceId }) {
            Task {
                try? await connect(to: device)
            }
        }
    }

    func untrustDevice(_ deviceId: String) {
        var trusted = trustedDeviceIds
        trusted.remove(deviceId)
        trustedDeviceIds = trusted

        // Disconnect
        disconnect(from: deviceId)
    }

    func isTrustedDevice(_ deviceId: String) -> Bool {
        trustedDeviceIds.contains(deviceId)
    }

    // MARK: - Auto-Connect

    private func autoConnectIfTrusted(_ device: ProximityDevice) {
        guard autoConnectEnabled else { return }
        guard isTrustedDevice(device.id) else { return }
        guard !connectedDevices.contains(device.id) else { return }

        // Auto-connect only if very close (< 2 meters)
        if let distance = device.estimatedDistance, distance < 2.0 {
            print("[Proximity] Auto-connecting to trusted device: \(device.name)")
            Task {
                try? await connect(to: device)
            }
        }
    }

    // MARK: - Helpers

    private func getDeviceId() -> String {
        DeviceIdentityManager.shared.deviceFingerprint.deviceId
    }

    private func hasLocalLLM() -> Bool {
        return ChatModeManager.shared.isModeAvailable(.local)
    }

    private func estimateDistance(rssi: Int) -> Double {
        // RSSI to distance estimation (rough)
        let txPower = -59.0 // Measured power at 1 meter
        if rssi == 0 {
            return -1.0
        }

        let ratio = Double(rssi) / txPower
        if ratio < 1.0 {
            return pow(ratio, 10)
        } else {
            let distance = 0.89976 * pow(ratio, 7.7095) + 0.111
            return distance
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ProximityDiscoveryManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[Proximity] Bluetooth powered on")
            if isScanning {
                central.scanForPeripherals(withServices: [serviceUUID], options: nil)
            }
        case .poweredOff:
            print("[Proximity] Bluetooth powered off")
        case .unauthorized:
            print("[Proximity] Bluetooth unauthorized")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let deviceId = peripheral.identifier.uuidString

        let distance = estimateDistance(rssi: RSSI.intValue)

        let device = ProximityDevice(
            id: deviceId,
            name: name,
            connectionType: .bluetooth,
            rssi: RSSI.intValue,
            estimatedDistance: distance,
            peripheral: peripheral
        )

        // Update or add device
        if let index = discoveredDevices.firstIndex(where: { $0.id == deviceId }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }

        // Auto-connect if trusted
        autoConnectIfTrusted(device)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension ProximityDiscoveryManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("[Proximity] Peripheral powered on")
            if isScanning {
                startAdvertising()
            }
        case .poweredOff:
            print("[Proximity] Peripheral powered off")
        default:
            break
        }
    }
}

// MARK: - MCSessionDelegate

extension ProximityDiscoveryManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("[Proximity] Multipeer connected: \(peerID.displayName)")
                self.connectedDevices.insert(peerID.displayName)
            case .connecting:
                print("[Proximity] Multipeer connecting: \(peerID.displayName)")
            case .notConnected:
                print("[Proximity] Multipeer disconnected: \(peerID.displayName)")
                self.connectedDevices.remove(peerID.displayName)
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle P2P messages
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ProximityDiscoveryManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept if trusted
        let deviceId = String(data: context ?? Data(), encoding: .utf8) ?? peerID.displayName

        if isTrustedDevice(deviceId) {
            print("[Proximity] Auto-accepting invitation from trusted peer: \(peerID.displayName)")
            invitationHandler(true, session)
        } else {
            print("[Proximity] Received invitation from untrusted peer: \(peerID.displayName)")
            // For now, reject untrusted
            invitationHandler(false, nil)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension ProximityDiscoveryManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("[Proximity] Found Multipeer peer: \(peerID.displayName)")

        let deviceId = info?["deviceId"] ?? peerID.displayName
        let hasLocalLLM = info?["hasLocalLLM"] == "true"

        let device = ProximityDevice(
            id: deviceId,
            name: peerID.displayName,
            connectionType: .multipeer,
            hasLocalLLM: hasLocalLLM,
            peerID: peerID
        )

        // Update or add device
        if let index = discoveredDevices.firstIndex(where: { $0.id == deviceId }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }

        // Auto-connect if trusted
        if isTrustedDevice(deviceId) {
            print("[Proximity] Auto-inviting trusted peer: \(peerID.displayName)")
            browser.invitePeer(peerID, to: session!, withContext: getDeviceId().data(using: .utf8), timeout: 30)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[Proximity] Lost Multipeer peer: \(peerID.displayName)")

        // Remove from discovered devices
        discoveredDevices.removeAll(where: { $0.name == peerID.displayName })
    }
}

// MARK: - Data Models

struct ProximityDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let connectionType: ConnectionType
    var rssi: Int?
    var estimatedDistance: Double?
    var hasLocalLLM: Bool = false

    // Bluetooth
    var peripheral: CBPeripheral?

    // MultipeerConnectivity
    var peerID: MCPeerID?

    // QR Code
    var qrCodeURL: String?

    static func == (lhs: ProximityDevice, rhs: ProximityDevice) -> Bool {
        lhs.id == rhs.id
    }
}

enum ConnectionType: String, Codable {
    case bluetooth = "Bluetooth"
    case multipeer = "Wi-Fi Direct"
    case qrCode = "QR Code"
}
