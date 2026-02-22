import SwiftUI

/// Survival Dashboard - Unified access point for 5 killer survival features
/// Emergency Manual, Offline Map, Digital Vault, Mental Care, Barter Board
struct SurvivalDashboardView: View {
    @State private var selectedTool: SurvivalTool?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)

                        Text("Survival Suite")
                            .font(.title.bold())

                        Text("災害・緊急時のオールインワンツール")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)

                    // Tools Grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        // 1. Emergency Manual
                        SurvivalCard(
                            title: "Emergency Manual",
                            subtitle: "緊急時マニュアル",
                            icon: "book.fill",
                            color: .red,
                            description: "応急処置・災害対応・サバイバルスキル"
                        ) {
                            selectedTool = .manual
                        }

                        // 2. Offline Map
                        SurvivalCard(
                            title: "Offline Map",
                            subtitle: "オフライン地図",
                            icon: "map.fill",
                            color: .blue,
                            description: "避難所マップと経路案内"
                        ) {
                            selectedTool = .map
                        }

                        // 3. Digital Vault
                        SurvivalCard(
                            title: "Digital Vault",
                            subtitle: "デジタル金庫",
                            icon: "lock.shield.fill",
                            color: .purple,
                            description: "重要書類の暗号化保存"
                        ) {
                            selectedTool = .vault
                        }

                        // 4. Mental Care
                        SurvivalCard(
                            title: "Mental Care",
                            subtitle: "メンタルケア",
                            icon: "heart.fill",
                            color: .pink,
                            description: "AIカウンセリングとゲーム"
                        ) {
                            selectedTool = .therapy
                        }

                        // 5. Barter Board
                        SurvivalCard(
                            title: "Barter Board",
                            subtitle: "物々交換",
                            icon: "arrow.left.arrow.right",
                            color: .green,
                            description: "P2P物々交換掲示板"
                        ) {
                            selectedTool = .barter
                        }
                    }
                    .padding(.horizontal)

                    // Info Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("このツールについて")
                                .font(.headline)
                        }

                        Text("Survival Suiteは、災害や緊急事態に備えた5つの機能を統合したオールインワンツールです。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            FeaturePoint(icon: "wifi.slash", text: "オフライン対応: インターネット不要")
                            FeaturePoint(icon: "lock.fill", text: "暗号化: AES-256で安全に保存")
                            FeaturePoint(icon: "network", text: "P2Pメッシュ: 近隣デバイスと連携")
                            FeaturePoint(icon: "yensign.circle", text: "完全無料: トークン消費なし")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Safety Tips
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("安全のために")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            SafetyTip(text: "定期的にデジタル金庫に重要書類をバックアップ")
                            SafetyTip(text: "避難所の場所を事前に確認")
                            SafetyTip(text: "P2P取引は公共の場所で行う")
                            SafetyTip(text: "メンタルケアを積極的に活用")
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Survival Suite")
            .sheet(item: $selectedTool) { tool in
                destinationView(for: tool)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for tool: SurvivalTool) -> some View {
        switch tool {
        case .manual:
            EmergencyKnowledgeBaseView()
        case .map:
            OfflineMapView()
        case .vault:
            DigitalVaultView()
        case .therapy:
            TherapyModeView()
        case .barter:
            BarterBoardView()
        }
    }
}

// MARK: - Survival Card

struct SurvivalCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundStyle(color)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature Point

struct FeaturePoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Safety Tip

struct SafetyTip: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.orange)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Survival Tool Enum

enum SurvivalTool: Identifiable {
    case manual, map, vault, therapy, barter

    var id: Self { self }
}

// MARK: - Therapy Mode View (Placeholder)

struct TherapyModeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.pink)

                VStack(spacing: 12) {
                    Text("メンタルケアモード")
                        .font(.title.bold())

                    Text("このモードでは、AIカウンセラーが\nあなたの心に寄り添います")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    NavigationLink(destination: SimpleGamesView()) {
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                            Text("ゲームで気分転換")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text("チャット画面でElioに話しかけることで\n心理カウンセリングを受けることもできます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 12) {
                    Text("こんな時に:")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        BulletPoint(text: "不安で眠れない")
                        BulletPoint(text: "気分が落ち込んでいる")
                        BulletPoint(text: "ストレスを感じる")
                        BulletPoint(text: "誰かと話したい")
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("メンタルケア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text("•")
                .foregroundStyle(.pink)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#Preview {
    SurvivalDashboardView()
}
