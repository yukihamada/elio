import SwiftUI

/// 超わかりやすいChatWebクイックトグル
struct ChatWebQuickToggle: View {
    @ObservedObject var chatModeManager: ChatModeManager
    @State private var isAnimating = false
    
    private var isChatWebMode: Bool {
        chatModeManager.currentMode == .chatweb
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isAnimating = true
                toggleChatWeb()
            }
            
            // Reset animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAnimating = false
            }
        }) {
            HStack(spacing: 8) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isChatWebMode ? 
                              LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing) :
                              LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: isChatWebMode ? "cloud.fill" : "cpu")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isChatWebMode ? .white : .gray)
                }
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                
                // Label
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChatWebMode ? "ChatWeb" : "Local")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isChatWebMode ? .blue : .primary)
                    
                    Text(isChatWebMode ? "クラウドAI" : "デバイス内")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isChatWebMode ? Color.blue.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isChatWebMode ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func toggleChatWeb() {
        if isChatWebMode {
            // Switch to Local
            chatModeManager.currentMode = .local
        } else {
            // Switch to ChatWeb - preconnect for speed
            chatModeManager.currentMode = .chatweb
            
            // Trigger preconnect in background
            Task {
                await preconnectChatWeb()
            }
        }
    }
    
    /// 高速接続のためのプリコネクト
    private func preconnectChatWeb() async {
        // Warm up the connection
        guard let backend = chatModeManager.chatwebBackend else { return }
        
        // Trigger a minimal request to establish connection
        // This happens in background, so next real request is instant
        _ = try? await backend.generate(
            messages: [Message(role: .user, content: "hi")],
            systemPrompt: "",
            settings: ModelSettings.default
        ) { _ in }
    }
}

#Preview {
    ChatWebQuickToggle(chatModeManager: ChatModeManager.shared)
}
