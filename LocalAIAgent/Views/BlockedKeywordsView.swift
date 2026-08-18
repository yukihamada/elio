
import SwiftUI

struct BlockedKeywordsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newKeyword: String = ""

    var body: some View {
        Form {
            Section(header: Text(String(localized: "parental.blocked_keywords.add_section_header"))) {
                HStack {
                    TextField(String(localized: "parental.blocked_keywords.add_placeholder"), text: $newKeyword)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    Button(String(localized: "common.add")) {
                        addKeyword()
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section(header: Text(String(localized: "parental.blocked_keywords.list_section_header"))) {
                if appState.parentalControlBlockedKeywords.isEmpty {
                    Text(String(localized: "parental.blocked_keywords.empty_list"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.parentalControlBlockedKeywords, id: \.self) { keyword in
                        HStack {
                            Text(keyword)
                            Spacer()
                            Button(action: { removeKeyword(keyword) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .onDelete(perform: deleteKeyword)
                }
            }
        }
        .navigationTitle(String(localized: "parental.blocked_keywords.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addKeyword() {
        let trimmedKeyword = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty && !appState.parentalControlBlockedKeywords.contains(trimmedKeyword) {
            appState.parentalControlBlockedKeywords.append(trimmedKeyword)
            newKeyword = ""
        }
    }

    private func removeKeyword(_ keyword: String) {
        if let index = appState.parentalControlBlockedKeywords.firstIndex(of: keyword) {
            appState.parentalControlBlockedKeywords.remove(at: index)
        }
    }

    private func deleteKeyword(at offsets: IndexSet) {
        appState.parentalControlBlockedKeywords.remove(atOffsets: offsets)
    }
}
