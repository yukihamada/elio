import SwiftUI
import PhotosUI

/// Digital Vault View - Secure document viewer with Face ID protection
struct DigitalVaultView: View {
    @StateObject private var vaultManager = DigitalVaultManager.shared
    @State private var showingAddDocument = false
    @State private var showingDocumentDetail: VaultDocument?
    @State private var showingError: VaultError?
    @State private var selectedCategory: DocumentCategory?

    var body: some View {
        NavigationView {
            Group {
                if vaultManager.isUnlocked {
                    documentList
                } else {
                    lockedView
                }
            }
            .navigationTitle("デジタル金庫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vaultManager.isUnlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingAddDocument = true }) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { vaultManager.lock() }) {
                            Image(systemName: "lock.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddDocument) {
                AddDocumentView()
            }
            .sheet(item: $showingDocumentDetail) { document in
                DocumentDetailView(document: document)
            }
            .alert(item: $showingError) { error in
                Alert(
                    title: Text("エラー"),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Locked View

    private var lockedView: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(.purple)

            VStack(spacing: 12) {
                Text("デジタル金庫")
                    .font(.title.bold())

                Text("重要な書類を安全に保管")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: unlockVault) {
                HStack {
                    Image(systemName: "faceid")
                    Text("Face IDでロック解除")
                }
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.purple)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "lock.shield", text: "AES-256暗号化")
                FeatureRow(icon: "faceid", text: "Face ID/Touch ID保護")
                FeatureRow(icon: "iphone", text: "デバイス内保存（クラウド同期なし）")
                FeatureRow(icon: "doc.text.viewfinder", text: "OCR自動テキスト抽出")
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Document List

    private var documentList: some View {
        VStack(spacing: 0) {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    CategoryChip(
                        category: nil,
                        isSelected: selectedCategory == nil,
                        count: vaultManager.documents.count
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(DocumentCategory.allCases, id: \.self) { category in
                        let count = vaultManager.documents.filter { $0.category == category }.count
                        if count > 0 {
                            CategoryChip(
                                category: category,
                                isSelected: selectedCategory == category,
                                count: count
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGray6))

            if filteredDocuments.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredDocuments) { document in
                        DocumentRow(document: document)
                            .onTapGesture {
                                vaultManager.resetAutoLockTimer()
                                showingDocumentDetail = document
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteDocument(document)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var filteredDocuments: [VaultDocument] {
        if let category = selectedCategory {
            return vaultManager.documents.filter { $0.category == category }
        }
        return vaultManager.documents
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("書類がありません")
                .font(.title3.bold())

            Text("右上の＋ボタンから\n重要書類を追加できます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Actions

    private func unlockVault() {
        Task {
            do {
                try await vaultManager.unlock()
            } catch let error as VaultError {
                showingError = error
            } catch {
                showingError = .authenticationFailed
            }
        }
    }

    private func deleteDocument(_ document: VaultDocument) {
        Task {
            do {
                try await vaultManager.deleteDocument(id: document.id)
            } catch let error as VaultError {
                showingError = error
            }
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: DocumentCategory?
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let category = category {
                    Image(systemName: category.icon)
                    Text(category.rawValue)
                } else {
                    Image(systemName: "folder")
                    Text("すべて")
                }
                Text("(\(count))")
                    .font(.caption)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.purple : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: VaultDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.category.icon)
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 40, height: 40)
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)

                HStack {
                    Text(document.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(document.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add Document View

struct AddDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vaultManager = DigitalVaultManager.shared

    @State private var selectedImage: UIImage?
    @State private var documentName = ""
    @State private var selectedCategory: DocumentCategory = .other
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var isProcessing = false
    @State private var extractedText = ""
    @State private var showingError: VaultError?

    var body: some View {
        NavigationView {
            Form {
                Section("書類") {
                    TextField("書類名", text: $documentName)

                    Picker("カテゴリ", selection: $selectedCategory) {
                        ForEach(DocumentCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                            }
                            .tag(category)
                        }
                    }
                }

                Section("画像") {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    HStack {
                        Button(action: { showingCamera = true }) {
                            Label("カメラで撮影", systemImage: "camera")
                        }

                        Spacer()

                        Button(action: { showingImagePicker = true }) {
                            Label("写真から選択", systemImage: "photo")
                        }
                    }
                }

                if !extractedText.isEmpty {
                    Section("抽出されたテキスト") {
                        Text(extractedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("書類を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveDocument()
                    }
                    .disabled(selectedImage == nil || documentName.isEmpty || isProcessing)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage, sourceType: .photoLibrary)
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(image: $selectedImage, sourceType: .camera)
            }
            .onChange(of: selectedImage) { _, newImage in
                if let image = newImage {
                    extractTextFromImage(image)
                }
            }
            .alert(item: $showingError) { error in
                Alert(
                    title: Text("エラー"),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text("OK"))
                )
            }
            .overlay {
                if isProcessing {
                    ProgressView("処理中...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func extractTextFromImage(_ image: UIImage) {
        isProcessing = true
        Task {
            do {
                let text = try await vaultManager.extractText(from: image)
                await MainActor.run {
                    extractedText = text
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                }
            }
        }
    }

    private func saveDocument() {
        guard let image = selectedImage else { return }

        isProcessing = true
        Task {
            do {
                try await vaultManager.addDocument(
                    image: image,
                    name: documentName,
                    category: selectedCategory
                )
                await MainActor.run {
                    isProcessing = false
                    dismiss()
                }
            } catch let error as VaultError {
                await MainActor.run {
                    isProcessing = false
                    showingError = error
                }
            }
        }
    }
}

// MARK: - Document Detail View

struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vaultManager = DigitalVaultManager.shared
    let document: VaultDocument

    @State private var documentImage: UIImage?
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var showingError: VaultError?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image = documentImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 5)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 300)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: document.category.icon)
                                .foregroundStyle(.purple)
                            Text(document.category.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text("作成日: \(document.createdAt.formatted(date: .long, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let text = document.extractedText, !text.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("抽出されたテキスト")
                                .font(.headline)

                            Text(text)
                                .font(.subheadline)
                                .padding()
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Button(action: exportDocument) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("PDFとしてエクスポート")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle(document.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadImage()
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            .alert(item: $showingError) { error in
                Alert(
                    title: Text("エラー"),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func loadImage() {
        do {
            documentImage = try vaultManager.getDocumentImage(id: document.id)
        } catch let error as VaultError {
            showingError = error
        } catch {}
    }

    private func exportDocument() {
        do {
            shareURL = try vaultManager.exportDocument(id: document.id)
            showingShareSheet = true
        } catch let error as VaultError {
            showingError = error
        } catch {}
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Identifiable Extension for VaultError

extension VaultError: Identifiable {
    var id: String {
        localizedDescription
    }
}

#Preview {
    DigitalVaultView()
}
