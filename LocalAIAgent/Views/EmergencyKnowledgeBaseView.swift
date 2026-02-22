import SwiftUI
import WebKit

/// Emergency Knowledge Base Viewer - Offline HTML viewer
/// Displays comprehensive emergency and survival information
struct EmergencyKnowledgeBaseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            ZStack {
                // WebView
                EmergencyKBWebView(isLoading: $isLoading)
                    .ignoresSafeArea()

                // Loading overlay
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)

                            Text("ナレッジベースを読み込み中...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(30)
                        .background(Color(.systemBackground).opacity(0.95))
                        .cornerRadius(16)
                    }
                }
            }
            .navigationTitle("緊急ナレッジベース")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// WebKit WebView wrapper for displaying HTML content
struct EmergencyKBWebView: UIViewRepresentable {
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear

        // Load HTML from bundle
        if let htmlPath = Bundle.main.path(forResource: "EmergencyKnowledgeBaseViewer", ofType: "html"),
           let htmlContent = try? String(contentsOfFile: htmlPath, encoding: .utf8) {
            webView.loadHTMLString(htmlContent, baseURL: Bundle.main.bundleURL)
        } else {
            // Fallback error message
            let errorHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body {
                        font-family: -apple-system, system-ui;
                        padding: 40px;
                        text-align: center;
                        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                        color: white;
                        min-height: 100vh;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    }
                    .error {
                        background: rgba(255,255,255,0.1);
                        padding: 30px;
                        border-radius: 20px;
                    }
                </style>
            </head>
            <body>
                <div class="error">
                    <h1>⚠️ エラー</h1>
                    <p>ナレッジベースファイルが見つかりませんでした</p>
                </div>
            </body>
            </html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}

#Preview {
    EmergencyKnowledgeBaseView()
}
