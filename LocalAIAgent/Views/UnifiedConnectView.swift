import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins
import CryptoKit

/// Unified connect view: QR scanner, my codes, friends & messages
/// Handles chatweb.ai, P2P peer pairing, and friend codes all in one camera
struct UnifiedConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var chatModeManager = ChatModeManager.shared
    @ObservedObject private var friendsManager = FriendsManager.shared
    @ObservedObject private var messagingManager = MessagingManager.shared
    @ObservedObject private var chatWebAPIKeyManager = ChatWebAPIKeyManager.shared
    @ObservedObject private var tokenManager = TokenManager.shared
    @State private var selectedTab: ConnectTab = .scan
    @State private var scannedResult: QRScanResult?
    @State private var showingResult = false
    @State private var showingBonusAlert = false

    enum ConnectTab: String, CaseIterable {
        case scan = "scan"
        case myCode = "mycode"
        case friends = "friends"

        var label: String {
            switch self {
            case .scan: return "Scan"
            case .myCode: return "My Code"
            case .friends: return "Friends"
            }
        }

        var icon: String {
            switch self {
            case .scan: return "qrcode.viewfinder"
            case .myCode: return "qrcode"
            case .friends: return "person.2.fill"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom tab bar
                tabBar

                // Content
                TabView(selection: $selectedTab) {
                    scanTab
                        .tag(ConnectTab.scan)

                    myCodeTab
                        .tag(ConnectTab.myCode)

                    friendsTab
                        .tag(ConnectTab.friends)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("接続結果", isPresented: $showingResult) {
                Button("OK") {}
            } message: {
                if let result = scannedResult {
                    Text(result.message)
                }
            }
            .alert("ボーナス獲得！", isPresented: $showingBonusAlert) {
                Button("OK") {}
            } message: {
                Text("ChatWeb.ai接続ボーナスとして10,000トークンを獲得しました！")
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ConnectTab.allCases, id: \.rawValue) { tab in
                Button(action: { withAnimation { selectedTab = tab } }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .background(
                        selectedTab == tab
                            ? AnyShapeStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.clear)
                    )
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Scan Tab

    private var scanTab: some View {
        ZStack {
            QRScannerRepresentable { code in
                handleScannedCode(code)
            }

            // Overlay frame
            VStack {
                Spacer()

                RoundedRectangle(cornerRadius: 20)
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 250, height: 250)

                Spacer()

                // Hint
                VStack(spacing: 8) {
                    Text("QRコードをスキャン")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("ChatWeb.ai・P2Pペア・フレンドコード対応")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - My Code Tab

    private var myCodeTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                // P2P pairing code + QR
                myPeerCodeSection

                // Friend QR code
                myFriendCodeSection

                // ChatWeb QR
                chatWebSection
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var myPeerCodeSection: some View {
        VStack(spacing: 16) {
            Label("P2P ペアリング", systemImage: "antenna.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.indigo)

            let code = PrivateServerManager.shared.pairingCode
            let qrString = "elio://peer?code=\(code)&name=\("Elio%20User")"

            if let qr = generateQRCode(from: qrString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(code)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .tracking(8)

            Text("近くのデバイスにこのコードを共有")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.tertiarySystemBackground))
        )
        .padding(.horizontal, 16)
    }

    private var myFriendCodeSection: some View {
        VStack(spacing: 16) {
            Label("フレンドコード", systemImage: "person.badge.plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.purple)

            let code = PrivateServerManager.shared.pairingCode
            // Use anonymous hash instead of real device ID
            let anonId = Data((DeviceIdentityManager.shared.deviceId + "elio-anon-salt-v1").utf8)
                .withUnsafeBytes { Array(SHA256.hash(data: $0).prefix(8)) }
                .map { String(format: "%02x", $0) }.joined()
            let qrString = "elio://friend?code=\(code)&name=\("Elio%20User")&id=\(anonId)"

            if let qr = generateQRCode(from: qrString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: {
                UIPasteboard.general.string = code
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }) {
                Label("コードをコピー", systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.tertiarySystemBackground))
        )
        .padding(.horizontal, 16)
    }

    private var chatWebSection: some View {
        VStack(spacing: 16) {
            Label("ChatWeb.ai", systemImage: "cloud.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.indigo)

            if let qr = generateQRCode(from: "https://chatweb.ai/?ref=elio&channel=elio") {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: {
                chatModeManager.setMode(.chatweb)
                grantConnectionBonus()
                dismiss()
            }) {
                Label("クラウドモードに切り替え", systemImage: "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.indigo.opacity(0.15))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
            }

            if chatWebAPIKeyManager.keyStatus == .valid {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("デバイス接続済み")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.tertiarySystemBackground))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Friends Tab

    private var friendsTab: some View {
        VStack(spacing: 0) {
            // Pending friend requests
            if !friendsManager.friendRequests.filter({ $0.status == .pending }).isEmpty {
                friendRequestsSection
            }

            if friendsManager.friends.isEmpty && messagingManager.conversations.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )

                    Text("まだフレンドがいません")
                        .font(.title3.bold())

                    Text("Scanタブでフレンドコードをスキャンするか\nMy Codeを共有して友達を追加")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    // Friends with conversations
                    if !messagingManager.conversations.isEmpty {
                        Section("メッセージ") {
                            ForEach(messagingManager.conversations.sorted(by: { $0.lastMessageAt > $1.lastMessageAt })) { conv in
                                NavigationLink(destination: DirectChatView(conversation: conv)) {
                                    ConversationRow(conversation: conv)
                                }
                            }
                        }
                    }

                    // All friends
                    Section("フレンド (\(friendsManager.friends.count))") {
                        ForEach(friendsManager.friends) { friend in
                            NavigationLink(destination: DirectChatView(
                                conversation: messagingManager.getOrCreateConversation(with: friend)
                            )) {
                                FriendRow(friend: friend)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    friendsManager.removeFriend(friend)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var friendRequestsSection: some View {
        VStack(spacing: 8) {
            ForEach(friendsManager.friendRequests.filter({ $0.status == .pending })) { request in
                HStack(spacing: 12) {
                    Circle()
                        .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(request.fromName.prefix(1)))
                                .font(.headline)
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.fromName)
                            .font(.subheadline.bold())
                        Text("フレンドリクエスト")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        Task { try? await friendsManager.acceptFriendRequest(request) }
                    }) {
                        Text("承認")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }

                    Button(action: {
                        friendsManager.rejectFriendRequest(request)
                    }) {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - QR Code Handling

    private func handleScannedCode(_ code: String) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if code.hasPrefix("elio://peer") {
            handlePeerCode(code)
        } else if code.hasPrefix("elio://friend") {
            handleFriendCode(code)
        } else if code.contains("chatweb.ai") || code.contains("teai.io") {
            handleChatWebCode(code)
        } else {
            // Try as 4-digit pairing code
            let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count == 4 && cleaned.allSatisfy({ $0.isNumber }) {
                handlePeerCode("elio://peer?code=\(cleaned)")
            } else {
                scannedResult = QRScanResult(success: false, message: "不明なQRコードです: \(code.prefix(50))")
                showingResult = true
            }
        }
    }

    private func handlePeerCode(_ code: String) {
        guard let components = URLComponents(string: code),
              let pairingCode = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            scannedResult = QRScanResult(success: false, message: "無効なペアリングコードです")
            showingResult = true
            return
        }

        Task {
            chatModeManager.p2p?.startBrowsing()
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if let server = chatModeManager.p2p?.findServer(byPairingCode: pairingCode) {
                do {
                    try await chatModeManager.p2p?.connect(to: server)
                    chatModeManager.p2p?.trustDevice(server)
                    chatModeManager.setMode(.privateP2P)
                    scannedResult = QRScanResult(success: true, message: "\(server.name) に接続しました！\nP2P推論モードに切り替えます。")
                    showingResult = true
                } catch {
                    scannedResult = QRScanResult(success: false, message: "接続に失敗: \(error.localizedDescription)")
                    showingResult = true
                }
            } else {
                scannedResult = QRScanResult(success: false, message: "デバイスが見つかりません。同じネットワークに接続してください。")
                showingResult = true
            }
        }
    }

    private func handleFriendCode(_ code: String) {
        guard let components = URLComponents(string: code),
              let pairingCode = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            scannedResult = QRScanResult(success: false, message: "無効なフレンドコードです")
            showingResult = true
            return
        }

        let name = components.queryItems?.first(where: { $0.name == "name" })?.value?.removingPercentEncoding

        Task {
            do {
                let friend = try await friendsManager.addFriend(pairingCode: pairingCode, name: name)
                scannedResult = QRScanResult(success: true, message: "\(friend.name) をフレンドに追加しました！")
                showingResult = true
                selectedTab = .friends
            } catch {
                scannedResult = QRScanResult(success: false, message: "フレンド追加に失敗: \(error.localizedDescription)")
                showingResult = true
            }
        }
    }

    private func handleChatWebCode(_ code: String) {
        chatModeManager.setMode(.chatweb)
        grantConnectionBonus()
        scannedResult = QRScanResult(success: true, message: "ChatWeb.ai クラウドモードに接続しました！")
        showingResult = true
    }

    private func grantConnectionBonus() {
        let key = "chatweb_connection_bonus_received"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        tokenManager.earn(10000, reason: .chatWebBonus)
        UserDefaults.standard.set(true, forKey: key)
        showingBonusAlert = true
    }

    // MARK: - QR Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - QR Scan Result

private struct QRScanResult {
    let success: Bool
    let message: String
}

// MARK: - QR Scanner (AVFoundation)

struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastScannedCode: String?
    private var lastScanTime: Date = .distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let session = captureSession, session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showNoCameraLabel()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)

        captureSession = session
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func showNoCameraLabel() {
        let label = UILabel()
        label.text = "カメラを利用できません"
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue else { return }

        // Debounce: prevent scanning the same code repeatedly
        let now = Date()
        if code == lastScannedCode && now.timeIntervalSince(lastScanTime) < 3.0 { return }
        lastScannedCode = code
        lastScanTime = now

        onCodeScanned?(code)
    }
}
