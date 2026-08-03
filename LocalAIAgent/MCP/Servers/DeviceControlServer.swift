import Foundation
import UIKit
import AVFoundation
import CoreImage
import UserNotifications

/// MCP Server for controlling device features: clipboard, flashlight, brightness,
/// battery info, device info, QR code generation, URL/app launching, haptic feedback.
final class DeviceControlServer: MCPServer {
    let id = "device_control"
    let name = "デバイス操作"
    let serverDescription = "クリップボード、ライト、明るさ、バッテリー、QRコード生成、アプリ起動、振動フィードバックなど"
    let icon = "iphone"

    func listTools() -> [MCPTool] {
        [
            // ── Clipboard ──
            MCPTool(
                name: "clipboard_read",
                description: "クリップボード（コピーした内容）を読み取ります",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "clipboard_write",
                description: "テキストをクリップボードにコピーします",
                inputSchema: MCPInputSchema(
                    properties: [
                        "text": MCPPropertySchema(type: "string", description: "コピーするテキスト"),
                    ],
                    required: ["text"]
                )
            ),

            // ── Flashlight ──
            MCPTool(
                name: "flashlight",
                description: "フラッシュライト（懐中電灯）のON/OFFを切り替えます",
                inputSchema: MCPInputSchema(
                    properties: [
                        "enabled": MCPPropertySchema(type: "boolean", description: "true=ON, false=OFF"),
                        "level": MCPPropertySchema(type: "number", description: "明るさ 0.0-1.0 (省略時=1.0)"),
                    ],
                    required: ["enabled"]
                )
            ),

            // ── Brightness ──
            MCPTool(
                name: "set_brightness",
                description: "画面の明るさを変更します (0.0=最暗〜1.0=最明)",
                inputSchema: MCPInputSchema(
                    properties: [
                        "level": MCPPropertySchema(type: "number", description: "明るさ 0.0-1.0"),
                    ],
                    required: ["level"]
                )
            ),
            MCPTool(
                name: "get_brightness",
                description: "現在の画面の明るさを取得します",
                inputSchema: MCPInputSchema()
            ),

            // ── Device Info ──
            MCPTool(
                name: "device_info",
                description: "デバイス情報を取得（モデル名、OS、バッテリー残量、ストレージ空き容量、メモリ）",
                inputSchema: MCPInputSchema()
            ),

            // ── Battery ──
            MCPTool(
                name: "battery_status",
                description: "バッテリー残量と充電状態を取得します",
                inputSchema: MCPInputSchema()
            ),

            // ── QR Code ──
            MCPTool(
                name: "generate_qr",
                description: "テキストやURLからQRコードを生成します。結果はBase64画像で返されます。",
                inputSchema: MCPInputSchema(
                    properties: [
                        "content": MCPPropertySchema(type: "string", description: "QRコードに埋め込む文字列やURL"),
                        "size": MCPPropertySchema(type: "number", description: "画像サイズ(px, 省略時=256)"),
                    ],
                    required: ["content"]
                )
            ),

            // ── Open URL / App ──
            MCPTool(
                name: "open_url",
                description: "URLを開きます。Webサイト、アプリのURLスキーム(tel:, mailto:, maps:等)にも対応。",
                inputSchema: MCPInputSchema(
                    properties: [
                        "url": MCPPropertySchema(type: "string", description: "開くURL (https://, tel:, mailto:, maps:, shortcuts:// 等)"),
                    ],
                    required: ["url"]
                )
            ),

            // ── Haptic Feedback ──
            MCPTool(
                name: "haptic",
                description: "振動フィードバックを実行します（通知、確認、注意など）",
                inputSchema: MCPInputSchema(
                    properties: [
                        "type": MCPPropertySchema(type: "string", description: "振動タイプ: success, warning, error, light, medium, heavy, selection"),
                    ],
                    required: ["type"]
                )
            ),

            // ── Timer ──
            MCPTool(
                name: "set_timer",
                description: "指定秒数後にローカル通知でリマインドします",
                inputSchema: MCPInputSchema(
                    properties: [
                        "seconds": MCPPropertySchema(type: "number", description: "秒数"),
                        "message": MCPPropertySchema(type: "string", description: "通知メッセージ"),
                    ],
                    required: ["seconds", "message"]
                )
            ),
        ]
    }

    @MainActor
    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "clipboard_read":
            return clipboardRead()
        case "clipboard_write":
            return clipboardWrite(arguments)
        case "flashlight":
            return flashlight(arguments)
        case "set_brightness":
            return setBrightness(arguments)
        case "get_brightness":
            return getBrightness()
        case "device_info":
            return deviceInfo()
        case "battery_status":
            return batteryStatus()
        case "generate_qr":
            return generateQR(arguments)
        case "open_url":
            return await openURL(arguments)
        case "haptic":
            return hapticFeedback(arguments)
        case "set_timer":
            return await setTimer(arguments)
        default:
            return MCPResult(content: [.text("[ERROR] Unknown tool: \(name)")], isError: true)
        }
    }

    // MARK: - Clipboard

    @MainActor
    private func clipboardRead() -> MCPResult {
        let pasteboard = UIPasteboard.general
        if let text = pasteboard.string {
            return MCPResult(content: [.text(text)])
        } else if pasteboard.hasImages {
            return MCPResult(content: [.text("[クリップボードに画像があります（テキストではありません）]")])
        } else {
            return MCPResult(content: [.text("[クリップボードは空です]")])
        }
    }

    @MainActor
    private func clipboardWrite(_ args: [String: JSONValue]) -> MCPResult {
        guard let text = args["text"]?.stringValue else {
            return MCPResult(content: [.text("[ERROR] 'text' is required")], isError: true)
        }
        UIPasteboard.general.string = text
        return MCPResult(content: [.text("クリップボードにコピーしました (\(text.count)文字)")])
    }

    // MARK: - Flashlight

    private func flashlight(_ args: [String: JSONValue]) -> MCPResult {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return MCPResult(content: [.text("[ERROR] このデバイスにフラッシュライトはありません")], isError: true)
        }

        let enabled = args["enabled"]?.boolValue ?? false
        let level = args["level"]?.doubleValue ?? 1.0

        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: Float(min(max(level, 0.01), 1.0)))
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            return MCPResult(content: [.text("フラッシュライト: \(enabled ? "ON (明るさ \(Int(level * 100))%)" : "OFF")")])
        } catch {
            return MCPResult(content: [.text("[ERROR] \(error.localizedDescription)")], isError: true)
        }
    }

    // MARK: - Brightness

    @MainActor
    private func setBrightness(_ args: [String: JSONValue]) -> MCPResult {
        guard let level = args["level"]?.doubleValue else {
            return MCPResult(content: [.text("[ERROR] 'level' is required (0.0-1.0)")], isError: true)
        }
        let clamped = min(max(level, 0.0), 1.0)
        UIScreen.main.brightness = CGFloat(clamped)
        return MCPResult(content: [.text("画面の明るさを \(Int(clamped * 100))% に設定しました")])
    }

    @MainActor
    private func getBrightness() -> MCPResult {
        let level = UIScreen.main.brightness
        return MCPResult(content: [.text("現在の画面の明るさ: \(Int(level * 100))%")])
    }

    // MARK: - Device Info

    @MainActor
    private func deviceInfo() -> MCPResult {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let processInfo = ProcessInfo.processInfo

        let storage = getStorageInfo()
        let memory = processInfo.physicalMemory
        let memoryGB = String(format: "%.1f", Double(memory) / 1_073_741_824)

        let info = """
        デバイス: \(device.name)
        モデル: \(device.model)
        OS: \(device.systemName) \(device.systemVersion)
        バッテリー: \(Int(device.batteryLevel * 100))% (\(batteryStateString(device.batteryState)))
        メモリ: \(memoryGB) GB
        ストレージ空き: \(storage.free) / \(storage.total)
        画面の明るさ: \(Int(UIScreen.main.brightness * 100))%
        言語: \(Locale.current.language.languageCode?.identifier ?? "unknown")
        タイムゾーン: \(TimeZone.current.identifier)
        """
        return MCPResult(content: [.text(info)])
    }

    // MARK: - Battery

    @MainActor
    private func batteryStatus() -> MCPResult {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = Int(device.batteryLevel * 100)
        let state = batteryStateString(device.batteryState)
        return MCPResult(content: [.text("バッテリー: \(level)% (\(state))")])
    }

    private func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "充電中"
        case .full: return "満充電"
        case .unplugged: return "バッテリー駆動"
        case .unknown: return "不明"
        @unknown default: return "不明"
        }
    }

    // MARK: - QR Code

    private func generateQR(_ args: [String: JSONValue]) -> MCPResult {
        guard let content = args["content"]?.stringValue else {
            return MCPResult(content: [.text("[ERROR] 'content' is required")], isError: true)
        }
        let size = args["size"]?.doubleValue ?? 256

        guard let data = content.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return MCPResult(content: [.text("[ERROR] QRコード生成に失敗")], isError: true)
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else {
            return MCPResult(content: [.text("[ERROR] QRコード画像生成に失敗")], isError: true)
        }

        let scale = size / ciImage.extent.width
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return MCPResult(content: [.text("[ERROR] 画像変換に失敗")], isError: true)
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let pngData = uiImage.pngData() else {
            return MCPResult(content: [.text("[ERROR] PNG変換に失敗")], isError: true)
        }

        let base64 = pngData.base64EncodedString()

        // Also save to clipboard for easy sharing
        UIPasteboard.general.image = uiImage

        return MCPResult(content: [
            .text("QRコードを生成しました (\(Int(size))x\(Int(size))px)。クリップボードにもコピー済み。\n内容: \(content)"),
            MCPContent(type: "image", data: base64, mimeType: "image/png")
        ])
    }

    // MARK: - Open URL

    @MainActor
    private func openURL(_ args: [String: JSONValue]) async -> MCPResult {
        guard let urlString = args["url"]?.stringValue,
              let url = URL(string: urlString) else {
            return MCPResult(content: [.text("[ERROR] 有効なURLが必要です")], isError: true)
        }

        let success = await UIApplication.shared.open(url)
        if success {
            return MCPResult(content: [.text("\(urlString) を開きました")])
        } else {
            return MCPResult(content: [.text("[ERROR] URLを開けませんでした: \(urlString)")], isError: true)
        }
    }

    // MARK: - Haptic

    @MainActor
    private func hapticFeedback(_ args: [String: JSONValue]) -> MCPResult {
        let type = args["type"]?.stringValue ?? "medium"

        switch type {
        case "success":
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning":
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error":
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "light":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "medium":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case "heavy":
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "selection":
            UISelectionFeedbackGenerator().selectionChanged()
        default:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        return MCPResult(content: [.text("振動フィードバック: \(type)")])
    }

    // MARK: - Timer

    private func setTimer(_ args: [String: JSONValue]) async -> MCPResult {
        guard let seconds = args["seconds"]?.doubleValue else {
            return MCPResult(content: [.text("[ERROR] 'seconds' is required")], isError: true)
        }
        let message = args["message"]?.stringValue ?? "タイマー完了"

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let content = UNMutableNotificationContent()
        content.title = "Elio タイマー"
        content.body = message
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        do {
            try await center.add(request)
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            let timeStr = mins > 0 ? "\(mins)分\(secs)秒" : "\(secs)秒"
            return MCPResult(content: [.text("\(timeStr)後にリマインドします: \"\(message)\"")])
        } catch {
            return MCPResult(content: [.text("[ERROR] \(error.localizedDescription)")], isError: true)
        }
    }

    // MARK: - Helpers

    private func getStorageInfo() -> (free: String, total: String) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let free = (attrs[.systemFreeSize] as? Int64) ?? 0
            let total = (attrs[.systemSize] as? Int64) ?? 0
            return (formatBytes(free), formatBytes(total))
        } catch {
            return ("不明", "不明")
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - JSONValue helpers

extension JSONValue {
    var doubleValue: Double? {
        switch self {
        case .double(let n): return n
        case .int(let n): return Double(n)
        case .string(let s): return Double(s)
        default: return nil
        }
    }
}
