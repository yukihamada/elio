import SwiftUI

// MARK: - Skill Marketplace View

struct SkillMarketplaceView: View {
    @StateObject private var manager = SkillMarketplaceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSort: SkillMarketplaceManager.SortOption = .popular
    @State private var selectedCategory: SkillCategory?
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var selectedSkill: Skill?
    @State private var showingDetail = false
    @State private var showingPublish = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab selector
                    tabSelector
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if selectedTab == 0 {
                        browseTab
                    } else {
                        mySkillsTab
                    }
                }
            }
            .navigationTitle("スキルストア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingPublish = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.purple)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await manager.fetchSkills(sort: selectedSort)
            }
            .sheet(isPresented: $showingDetail) {
                if let skill = selectedSkill {
                    SkillDetailView(skill: skill)
                }
            }
            .sheet(isPresented: $showingPublish) {
                SkillPublishView()
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "ストア", icon: "storefront", index: 0)
            tabButton(title: "マイスキル", icon: "tray.full", index: 1)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedTab == index ? Color.accentColor.opacity(0.15) : Color.clear)
                    .padding(2)
            )
            .foregroundStyle(selectedTab == index ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Browse Tab

    private var browseTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Search bar
                searchBar
                    .padding(.horizontal, 20)

                // Category filter
                categoryFilter

                // Sort picker
                Picker("Sort", selection: $selectedSort) {
                    ForEach(SkillMarketplaceManager.SortOption.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .onChange(of: selectedSort) { _, _ in
                    Task { await fetchWithFilters() }
                }

                // Content
                if manager.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if manager.skills.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(manager.skills) { skill in
                            skillCard(skill)
                                .onTapGesture {
                                    selectedSkill = skill
                                    showingDetail = true
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - My Skills Tab

    private var mySkillsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                if manager.installedSkills.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("インストール済みスキルはありません")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        Text("ストアからスキルをインストールしてみましょう")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(manager.installedSkills) { installed in
                        installedSkillCard(installed)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            TextField("スキルを検索...", text: $searchText)
                .font(.system(size: 15))
                .textFieldStyle(.plain)
                .onSubmit {
                    Task { await fetchWithFilters() }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    Task { await fetchWithFilters() }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "すべて", category: nil)
                ForEach(SkillCategory.allCases, id: \.self) { category in
                    categoryChip(title: category.shortName, category: category)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func categoryChip(title: String, category: SkillCategory?) -> some View {
        let isSelected = selectedCategory == category

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
            Task { await fetchWithFilters() }
        }) {
            HStack(spacing: 4) {
                if let category = category {
                    Image(systemName: category.iconName)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.cardBackground)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.subtleSeparator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skill Card

    private func skillCard(_ skill: Skill) -> some View {
        let isInstalled = manager.isInstalled(skill.id)

        return HStack(spacing: 14) {
            // Icon
            skillIcon(category: skill.category, iconUrl: skill.iconUrl)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 8) {
                    Label(skill.authorName, systemImage: "person")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(skill.category.shortName)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(skill.category.color.opacity(0.12))
                        .foregroundStyle(skill.category.color)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    // Rating
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", skill.averageRating))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("(\(skill.ratingCount))")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    // Install count
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                        Text("\(skill.installCount)")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Price / Install
            VStack(spacing: 4) {
                if isInstalled {
                    Text("インストール済み")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                } else if skill.priceTokens == 0 {
                    Text("無料")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 11))
                        Text("\(skill.priceTokens)")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    // MARK: - Installed Skill Card

    private func installedSkillCard(_ installed: InstalledSkill) -> some View {
        HStack(spacing: 14) {
            // Icon
            skillIcon(category: installed.category, iconUrl: installed.iconUrl)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(installed.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(installed.authorName, systemImage: "person")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("v\(installed.version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Enable/Disable toggle
            Toggle("", isOn: Binding(
                get: { installed.isEnabled },
                set: { _ in manager.toggleSkill(installed) }
            ))
            .labelsHidden()
            .tint(installed.category.color)

            // Delete button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    manager.uninstallSkill(installed)
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    installed.isEnabled ? installed.category.color.opacity(0.3) : Color.subtleSeparator,
                    lineWidth: installed.isEnabled ? 1.5 : 0.5
                )
        )
    }

    // MARK: - Skill Icon

    private func skillIcon(category: SkillCategory, iconUrl: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(category.color.opacity(0.15))
                .frame(width: 48, height: 48)

            if let iconUrl = iconUrl, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } placeholder: {
                    Image(systemName: category.iconName)
                        .font(.system(size: 22))
                        .foregroundStyle(category.color)
                }
            } else {
                Image(systemName: category.iconName)
                    .font(.system(size: 22))
                    .foregroundStyle(category.color)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("スキルが見つかりません")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Text("別のカテゴリやキーワードで検索してみてください")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func fetchWithFilters() async {
        await manager.fetchSkills(
            sort: selectedSort,
            category: selectedCategory,
            search: searchText.isEmpty ? nil : searchText
        )
    }
}

#Preview {
    SkillMarketplaceView()
}
