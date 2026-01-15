import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 会話をSNSにシェアするためのカード画像を生成するビュー
struct ShareCardView: View {
    let userMessage: String
    let assistantMessage: String
    let modelName: String

    private let maxMessageLength = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)

                Text("ElioChat")
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                Text(modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            // User message
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.blue)
                    Text("あなた")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(truncateMessage(userMessage))
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Assistant message
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("ElioChat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(truncateMessage(assistantMessage))
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.purple.opacity(0.05))

            // Footer
            HStack {
                Text("完全オフライン・プライベートAI")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("elio.love")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }

    private func truncateMessage(_ message: String) -> String {
        if message.count <= maxMessageLength {
            return message
        }
        return String(message.prefix(maxMessageLength)) + "..."
    }
}

/// シェアカードを画像として生成するユーティリティ
@MainActor
struct ShareCardGenerator {
    #if canImport(UIKit)
    /// SwiftUIビューを画像に変換
    static func generateImage(userMessage: String, assistantMessage: String, modelName: String) -> UIImage? {
        let view = ShareCardView(
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            modelName: modelName
        )
        .frame(width: 350)
        .padding(20)
        .background(Color(UIColor.systemBackground))

        let controller = UIHostingController(rootView: view)
        controller.view.bounds = CGRect(origin: .zero, size: CGSize(width: 390, height: 600))

        // レイアウトを強制
        controller.view.layoutIfNeeded()

        // 実際のコンテンツサイズを取得
        let targetSize = controller.view.intrinsicContentSize
        controller.view.bounds = CGRect(origin: .zero, size: targetSize)
        controller.view.layoutIfNeeded()

        // 画像をレンダリング
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
    #endif
}

/// シェアカードを表示・共有するためのシート
struct ShareCardSheet: View {
    let userMessage: String
    let assistantMessage: String
    let modelName: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    #if canImport(UIKit)
    @State private var generatedImage: UIImage?
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(String(localized: "share.card.preview"))
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ShareCardView(
                        userMessage: userMessage,
                        assistantMessage: assistantMessage,
                        modelName: modelName
                    )
                    .padding(.horizontal, 20)

                    #if canImport(UIKit)
                    Button(action: shareCard) {
                        Label(String(localized: "share.card.button"), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                    #endif
                }
                .padding(.vertical, 20)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(String(localized: "share.card.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    #if canImport(UIKit)
    private func shareCard() {
        guard let image = ShareCardGenerator.generateImage(
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            modelName: modelName
        ) else { return }

        let activityVC = UIActivityViewController(
            activityItems: [image, "ElioChatで生成しました - elio.love"],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    #endif
}

#Preview {
    ShareCardView(
        userMessage: "今日の東京の天気を教えて",
        assistantMessage: "今日の東京は晴れで、最高気温は18度、最低気温は8度の予報です。午後から少し風が強くなる見込みですので、外出の際は上着があると安心です。",
        modelName: "Qwen3 1.7B"
    )
    .padding()
    .background(Color.gray.opacity(0.2))
}
