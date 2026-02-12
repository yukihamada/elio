import SwiftUI
import StoreKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationStack {
            List {
                // App Info Section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundStyle(.purple)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("ElioChat")
                                .font(.headline)
                            Text("バージョン \(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Actions Section
                Section {
                    Button(action: { requestReview() }) {
                        Label("アプリを評価", systemImage: "star.fill")
                    }

                    ShareLink(item: URL(string: "https://apps.apple.com/jp/app/elio-chat/id6757635481")!) {
                        Label("友達に共有", systemImage: "square.and.arrow.up")
                    }
                }

                // Privacy Section
                Section("プライバシー") {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("プライバシーポリシー", systemImage: "hand.raised.fill")
                    }

                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        Label("利用規約", systemImage: "doc.text.fill")
                    }
                }

                // Technical Info
                Section("技術情報") {
                    InfoRow(label: "AIエンジン", value: "llama.cpp")
                    InfoRow(label: "対応モデル", value: "GGUF形式")
                    InfoRow(label: "推論", value: "Metal GPU加速")
                }

                // Data Management
                Section("データ管理") {
                    Button(role: .destructive, action: { clearAllData() }) {
                        Label("すべての会話を削除", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }

                // Credits
                Section("クレジット") {
                    Text("このアプリはオープンソースライブラリを使用しています")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: "https://github.com/ggerganov/llama.cpp")!) {
                        HStack {
                            Text("llama.cpp")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("このアプリについて")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func clearAllData() {
        // This would clear conversation history
        // Implementation depends on AppState access
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("プライバシーポリシー")
                    .font(.title.bold())

                Group {
                    PolicySection(title: "データの収集について", content: """
                    ElioChatは、ユーザーのプライバシーを最優先に設計されています。

                    - すべてのAI処理はデバイス上で完結します
                    - 会話データは端末内のみに保存されます
                    - 外部サーバーへのデータ送信は行いません
                    """)

                    PolicySection(title: "保存されるデータ", content: """
                    アプリは以下のデータのみを保存します：

                    - 会話履歴（端末内のみ）
                    - アプリ設定（選択したモデルなど）
                    - ダウンロードしたAIモデル

                    これらのデータはすべて端末内に保存され、iCloudやその他のクラウドサービスには同期されません。
                    """)

                    PolicySection(title: "Web検索機能", content: """
                    Web検索機能を使用する場合、検索クエリがDuckDuckGo APIに送信されます。これは検索結果を取得するためにのみ使用され、個人を特定する情報は送信されません。

                    Web検索は完全にオプションであり、使用しなくてもアプリは動作します。
                    """)

                    PolicySection(title: "データの削除", content: """
                    設定画面からいつでもすべての会話データを削除できます。アプリを削除すると、すべてのデータが完全に消去されます。
                    """)
                }
            }
            .padding(20)
        }
        .navigationTitle("プライバシーポリシー")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("利用規約")
                    .font(.title.bold())

                Group {
                    PolicySection(title: "サービスの説明", content: """
                    ElioChatは、デバイス上で動作するAIアシスタントアプリケーションです。大規模言語モデル（LLM）を使用して、テキストベースの対話を提供します。
                    """)

                    PolicySection(title: "免責事項", content: """
                    - AIによる回答は参考情報であり、正確性を保証するものではありません
                    - 医療、法律、金融などの専門的なアドバイスについては、専門家にご相談ください
                    - AIモデルの出力結果について、開発者は責任を負いません
                    """)

                    PolicySection(title: "禁止事項", content: """
                    以下の行為は禁止されています：

                    - 違法な目的でのアプリの使用
                    - 有害なコンテンツの生成
                    - アプリの逆コンパイルや改変
                    """)

                    PolicySection(title: "知的財産権", content: """
                    アプリのデザイン、コード、およびコンテンツの著作権は開発者に帰属します。ただし、使用されているオープンソースライブラリは、それぞれのライセンスに従います。
                    """)
                }
            }
            .padding(20)
        }
        .navigationTitle("利用規約")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct PolicySection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AboutView()
}
