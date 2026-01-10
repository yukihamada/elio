import Foundation
import UIKit

final class ShortcutsServer: MCPServer {
    let id = "shortcuts"
    let name = "ショートカット"
    let serverDescription = "ショートカットアプリとの連携を行います"
    let icon = "command"

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "run_shortcut",
                description: "ショートカットを実行します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "name": MCPPropertySchema(type: "string", description: "ショートカットの名前"),
                        "input": MCPPropertySchema(type: "string", description: "ショートカットに渡す入力（オプション）")
                    ],
                    required: ["name"]
                )
            ),
            MCPTool(
                name: "open_shortcuts_app",
                description: "ショートカットアプリを開きます",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "open_url",
                description: "URLを開きます",
                inputSchema: MCPInputSchema(
                    properties: [
                        "url": MCPPropertySchema(type: "string", description: "開くURL")
                    ],
                    required: ["url"]
                )
            ),
            MCPTool(
                name: "open_settings",
                description: "設定アプリの特定のセクションを開きます",
                inputSchema: MCPInputSchema(
                    properties: [
                        "section": MCPPropertySchema(
                            type: "string",
                            description: "設定セクション",
                            enumValues: ["general", "wifi", "bluetooth", "notifications", "privacy", "battery"]
                        )
                    ]
                )
            ),
            MCPTool(
                name: "send_email",
                description: "メール作成画面を開きます",
                inputSchema: MCPInputSchema(
                    properties: [
                        "to": MCPPropertySchema(type: "string", description: "宛先メールアドレス"),
                        "subject": MCPPropertySchema(type: "string", description: "件名"),
                        "body": MCPPropertySchema(type: "string", description: "本文")
                    ]
                )
            ),
            MCPTool(
                name: "make_phone_call",
                description: "電話をかけます",
                inputSchema: MCPInputSchema(
                    properties: [
                        "number": MCPPropertySchema(type: "string", description: "電話番号")
                    ],
                    required: ["number"]
                )
            ),
            MCPTool(
                name: "send_message",
                description: "メッセージ作成画面を開きます",
                inputSchema: MCPInputSchema(
                    properties: [
                        "to": MCPPropertySchema(type: "string", description: "宛先電話番号"),
                        "body": MCPPropertySchema(type: "string", description: "本文")
                    ]
                )
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "run_shortcut":
            return try await runShortcut(arguments: arguments)
        case "open_shortcuts_app":
            return try await openShortcutsApp()
        case "open_url":
            return try await openURL(arguments: arguments)
        case "open_settings":
            return try await openSettings(arguments: arguments)
        case "send_email":
            return try await sendEmail(arguments: arguments)
        case "make_phone_call":
            return try await makePhoneCall(arguments: arguments)
        case "send_message":
            return try await sendMessage(arguments: arguments)
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func runShortcut(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let name = arguments["name"]?.stringValue else {
            throw MCPClientError.invalidArguments("name is required")
        }

        var urlString = "shortcuts://run-shortcut?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"

        if let input = arguments["input"]?.stringValue {
            urlString += "&input=text&text=\(input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input)"
        }

        guard let url = URL(string: urlString) else {
            throw MCPClientError.executionFailed("Invalid shortcut URL")
        }

        let opened = await MainActor.run {
            UIApplication.shared.open(url)
            return true
        }

        if opened {
            return MCPResult(content: [.text("ショートカット '\(name)' を実行しました")])
        } else {
            throw MCPClientError.executionFailed("ショートカットを開けませんでした")
        }
    }

    private func openShortcutsApp() async throws -> MCPResult {
        guard let url = URL(string: "shortcuts://") else {
            throw MCPClientError.executionFailed("Invalid URL")
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }

        return MCPResult(content: [.text("ショートカットアプリを開きました")])
    }

    private func openURL(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let urlString = arguments["url"]?.stringValue,
              let url = URL(string: urlString) else {
            throw MCPClientError.invalidArguments("Valid URL is required")
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }

        return MCPResult(content: [.text("URLを開きました: \(urlString)")])
    }

    private func openSettings(arguments: [String: JSONValue]) async throws -> MCPResult {
        let section = arguments["section"]?.stringValue ?? "general"

        let urlString: String
        switch section {
        case "wifi":
            urlString = "App-Prefs:root=WIFI"
        case "bluetooth":
            urlString = "App-Prefs:root=Bluetooth"
        case "notifications":
            urlString = "App-Prefs:root=NOTIFICATIONS_ID"
        case "privacy":
            urlString = "App-Prefs:root=Privacy"
        case "battery":
            urlString = "App-Prefs:root=BATTERY_USAGE"
        default:
            urlString = "App-Prefs:root=General"
        }

        guard let url = URL(string: urlString) else {
            throw MCPClientError.executionFailed("Invalid settings URL")
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }

        return MCPResult(content: [.text("設定(\(section))を開きました")])
    }

    private func sendEmail(arguments: [String: JSONValue]) async throws -> MCPResult {
        var urlString = "mailto:"

        if let to = arguments["to"]?.stringValue {
            urlString += to
        }

        var params: [String] = []

        if let subject = arguments["subject"]?.stringValue {
            params.append("subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject)")
        }

        if let body = arguments["body"]?.stringValue {
            params.append("body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body)")
        }

        if !params.isEmpty {
            urlString += "?" + params.joined(separator: "&")
        }

        guard let url = URL(string: urlString) else {
            throw MCPClientError.executionFailed("Invalid email URL")
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }

        return MCPResult(content: [.text("メール作成画面を開きました")])
    }

    private func makePhoneCall(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let number = arguments["number"]?.stringValue else {
            throw MCPClientError.invalidArguments("number is required")
        }

        let cleanNumber = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)

        guard let url = URL(string: "tel:\(cleanNumber)") else {
            throw MCPClientError.executionFailed("Invalid phone number")
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }

        return MCPResult(content: [.text("電話をかけています: \(number)")])
    }

    private func sendMessage(arguments: [String: JSONValue]) async throws -> MCPResult {
        var urlString = "sms:"

        if let to = arguments["to"]?.stringValue {
            urlString += to
        }

        if let body = arguments["body"]?.stringValue {
            urlString += "&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body)"
        }

        guard let url = URL(string: urlString) else {
            throw MCPClientError.executionFailed("Invalid message URL")
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }

        return MCPResult(content: [.text("メッセージ作成画面を開きました")])
    }
}
