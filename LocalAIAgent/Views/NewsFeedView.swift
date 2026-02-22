import SwiftUI
import SafariServices

// MARK: - News Feed View

struct NewsFeedView: View {
    @StateObject private var viewModel = NewsFeedViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Category tabs
                    categoryTabs

                    // Article list
                    if viewModel.isLoading && viewModel.articles.isEmpty {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    } else if viewModel.articles.isEmpty {
                        emptyState
                    } else {
                        articleList
                    }
                }
            }
            .navigationTitle(String(localized: "news.title", defaultValue: "ニュース"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .searchable(
                text: $viewModel.searchQuery,
                prompt: String(localized: "news.search.prompt", defaultValue: "ニュースを検索...")
            )
            .onSubmit(of: .search) {
                Task { await viewModel.search() }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadInitial()
            }
        }
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" tab
                categoryPill(
                    label: String(localized: "news.category.all", defaultValue: "すべて"),
                    icon: "newspaper",
                    isSelected: viewModel.selectedCategory == nil
                ) {
                    viewModel.selectedCategory = nil
                    Task { await viewModel.refresh() }
                }

                ForEach(NewsCategory.allCases) { category in
                    categoryPill(
                        label: category.displayName,
                        icon: category.icon,
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        viewModel.selectedCategory = category
                        Task { await viewModel.refresh() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func categoryPill(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.indigo : Color(.tertiarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Article List

    private var articleList: some View {
        List {
            ForEach(viewModel.articles) { article in
                ArticleRow(article: article)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if viewModel.hasMore {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button(String(localized: "news.load_more", defaultValue: "もっと読む")) {
                            Task { await viewModel.loadMore() }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.indigo)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "news.empty", defaultValue: "ニュースがありません"))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            if let error = viewModel.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button(String(localized: "news.retry", defaultValue: "再読み込み")) {
                Task { await viewModel.refresh() }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.indigo)
            Spacer()
        }
    }
}

// MARK: - Article Row

struct ArticleRow: View {
    let article: NewsArticle
    @State private var showingSafari = false

    var body: some View {
        Button {
            showingSafari = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    if let summary = article.summary {
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let source = article.source {
                            Text(source)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.indigo)
                        }
                        if let date = article.publishedAt {
                            Text(date, style: .relative)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let imageURL = article.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.tertiarySystemBackground))
                                .frame(width: 72, height: 72)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSafari) {
            if let url = URL(string: article.url) {
                SafariView(url: url)
            }
        }
    }
}

// MARK: - Safari View (UIViewControllerRepresentable)

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - View Model

@MainActor
final class NewsFeedViewModel: ObservableObject {
    @Published var articles: [NewsArticle] = []
    @Published var selectedCategory: NewsCategory?
    @Published var searchQuery = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = false

    private var nextCursor: String?
    private let client = NewsAPIClient.shared

    func loadInitial() async {
        guard articles.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        error = nil
        nextCursor = nil

        do {
            let response = try await client.fetchArticles(
                category: selectedCategory,
                limit: 15
            )
            articles = response.articles
            nextCursor = response.nextCursor
            hasMore = response.nextCursor != nil
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true

        do {
            let response = try await client.fetchArticles(
                category: selectedCategory,
                limit: 15,
                cursor: cursor
            )
            articles.append(contentsOf: response.articles)
            nextCursor = response.nextCursor
            hasMore = response.nextCursor != nil
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func search() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            await refresh()
            return
        }

        isLoading = true
        error = nil

        do {
            let response = try await client.searchArticles(query: searchQuery, limit: 20)
            articles = response.articles
            hasMore = false
            nextCursor = nil
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
