import SwiftUI

/// Barter Board View - P2P marketplace for trading goods
struct BarterBoardView: View {
    @StateObject private var barterManager = BarterBoardManager.shared
    @State private var showingNewListing = false
    @State private var selectedTab: TabSelection = .available
    @State private var selectedListing: BarterListing?
    @State private var showingMatches = false

    enum TabSelection {
        case available, myListings
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("", selection: $selectedTab) {
                    Text("掲示板").tag(TabSelection.available)
                    Text("マイ出品(\(barterManager.myListings.count))").tag(TabSelection.myListings)
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                if selectedTab == .available {
                    availableListingsView
                } else {
                    myListingsView
                }
            }
            .navigationTitle("物々交換")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingNewListing = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingNewListing) {
                NewListingView()
            }
            .sheet(item: $selectedListing) { listing in
                ListingDetailView(listing: listing)
            }
        }
    }

    // MARK: - Available Listings

    private var availableListingsView: some View {
        Group {
            if barterManager.listings.filter({ $0.status == .active }).isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(barterManager.listings.filter { $0.status == .active }) { listing in
                        ListingRow(listing: listing, trustScore: barterManager.getTrustScore(for: listing.deviceId))
                            .onTapGesture {
                                selectedListing = listing
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - My Listings

    private var myListingsView: some View {
        Group {
            if barterManager.myListings.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "tray")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("出品がありません")
                        .font(.title3.bold())

                    Text("右上の＋ボタンから\n出品してみましょう")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(barterManager.myListings) { listing in
                        MyListingRow(listing: listing)
                            .onTapGesture {
                                selectedListing = listing
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("取引はまだありません")
                .font(.title3.bold())

            Text("メッシュネットワーク経由で\n近くの出品が表示されます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Listing Row

struct ListingRow: View {
    let listing: BarterListing
    let trustScore: TrustScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(listing.deviceName)
                            .font(.headline)

                        if let score = trustScore {
                            HStack(spacing: 4) {
                                Text(score.trustLevel.emoji)
                                Text(score.displayScore)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }

                    Text(listing.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("提供")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(listing.have)
                        .font(.subheadline.bold())
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("希望")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(listing.want)
                        .font(.subheadline.bold())
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let location = listing.location {
                HStack(spacing: 4) {
                    Image(systemName: "location")
                    Text(location)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let notes = listing.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}

struct MyListingRow: View {
    let listing: BarterListing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusBadge(status: listing.status)
                Spacer()
                Text(listing.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("提供")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(listing.have)
                        .font(.subheadline.bold())
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("希望")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(listing.want)
                        .font(.subheadline.bold())
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 8)
    }
}

struct StatusBadge: View {
    let status: BarterListing.ListingStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(displayName)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
    }

    private var icon: String {
        switch status {
        case .active: return "checkmark.circle"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private var displayName: String {
        switch status {
        case .active: return "募集中"
        case .completed: return "完了"
        case .cancelled: return "キャンセル"
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .active: return .green.opacity(0.1)
        case .completed: return .blue.opacity(0.1)
        case .cancelled: return .gray.opacity(0.1)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .active: return .green
        case .completed: return .blue
        case .cancelled: return .gray
        }
    }
}

// MARK: - New Listing View

struct NewListingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var barterManager = BarterBoardManager.shared

    @State private var have = ""
    @State private var want = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var isPosting = false
    @State private var showingError: Error?

    var body: some View {
        NavigationView {
            Form {
                Section("提供するもの") {
                    TextField("例: 水 2L", text: $have)
                    Text("自分が提供できるものを入力してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("希望するもの") {
                    TextField("例: お米 1kg", text: $want)
                    Text("交換で欲しいものを入力してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("場所（任意）") {
                    TextField("例: 300m先", text: $location)
                    Text("おおよその距離や目印を入力してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("備考（任意）") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                    Text("追加情報があれば入力してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.checkered")
                                .foregroundStyle(.blue)
                            Text("安全のために")
                                .font(.headline)
                        }

                        Text("• 公共の場所で取引しましょう\n• 貴重品の取引は避けましょう\n• 信頼スコアを参考にしましょう\n• 不審な取引は報告してください")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("新しい出品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("出品") {
                        postListing()
                    }
                    .disabled(have.isEmpty || want.isEmpty || isPosting)
                }
            }
            .overlay {
                if isPosting {
                    ProgressView("出品中...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func postListing() {
        isPosting = true
        Task {
            do {
                try await barterManager.postListing(
                    have: have,
                    want: want,
                    location: location.isEmpty ? nil : location,
                    notes: notes.isEmpty ? nil : notes
                )
                await MainActor.run {
                    isPosting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isPosting = false
                    showingError = error
                }
            }
        }
    }
}

// MARK: - Listing Detail View

struct ListingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var barterManager = BarterBoardManager.shared
    let listing: BarterListing

    @State private var matches: [BarterMatch] = []
    @State private var aiSuggestions = ""
    @State private var isLoadingSuggestions = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Listing Info
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(listing.deviceName)
                                    .font(.title2.bold())

                                if let trustScore = barterManager.getTrustScore(for: listing.deviceId) {
                                    HStack(spacing: 6) {
                                        Text(trustScore.trustLevel.emoji)
                                        Text(trustScore.trustLevel.displayName)
                                        Text("(\(trustScore.displayScore))")
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if listing.deviceId == barterManager.getDeviceId() {
                                StatusBadge(status: listing.status)
                            }
                        }

                        Divider()

                        TradeCard(have: listing.have, want: listing.want)

                        if let location = listing.location {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.blue)
                                Text(location)
                            }
                            .font(.subheadline)
                        }

                        if let notes = listing.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("備考")
                                    .font(.headline)
                                Text(notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()

                    // AI Suggestions
                    if listing.deviceId == barterManager.getDeviceId() && listing.status == .active {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.purple)
                                Text("AIマッチング")
                                    .font(.headline)
                            }

                            if isLoadingSuggestions {
                                ProgressView()
                            } else if !aiSuggestions.isEmpty {
                                Text(aiSuggestions)
                                    .font(.subheadline)
                            } else {
                                Button("マッチングを検索") {
                                    loadSuggestions()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(Color.purple.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Actions
                    if listing.deviceId == barterManager.getDeviceId() && listing.status == .active {
                        VStack(spacing: 12) {
                            Button(role: .destructive) {
                                cancelListing()
                            } label: {
                                Text("出品をキャンセル")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("取引詳細")
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

    private func loadSuggestions() {
        isLoadingSuggestions = true
        Task {
            let suggestions = await barterManager.getAISuggestions(for: listing)
            await MainActor.run {
                aiSuggestions = suggestions
                isLoadingSuggestions = false
            }
        }
    }

    private func cancelListing() {
        Task {
            try? await barterManager.cancelListing(id: listing.id)
            dismiss()
        }
    }
}

struct TradeCard: View {
    let have: String
    let want: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("提供")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(have)
                    .font(.title3.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("希望")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(want)
                    .font(.title3.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    BarterBoardView()
}
