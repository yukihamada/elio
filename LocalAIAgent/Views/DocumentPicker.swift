import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

struct PDFContent {
    let url: URL
    let text: String
    let pageImages: [UIImage]
    let pageCount: Int
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentSelected: (PDFContent) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentSelected: onDocumentSelected)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentSelected: (PDFContent) -> Void

        init(onDocumentSelected: @escaping (PDFContent) -> Void) {
            self.onDocumentSelected = onDocumentSelected
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to access security-scoped resource")
                return
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            // Extract content from PDF
            let content = extractContentFromPDF(at: url)

            DispatchQueue.main.async {
                self.onDocumentSelected(content)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled - no action needed
        }

        private func extractContentFromPDF(at url: URL) -> PDFContent {
            guard let pdfDocument = PDFDocument(url: url) else {
                return PDFContent(url: url, text: "", pageImages: [], pageCount: 0)
            }

            var fullText = ""
            var pageImages: [UIImage] = []
            let pageCount = pdfDocument.pageCount

            // Limit pages to prevent memory issues (max 10 pages for images)
            let maxPagesForImages = min(pageCount, 10)

            for pageIndex in 0..<pageCount {
                if let page = pdfDocument.page(at: pageIndex) {
                    // Extract text
                    if let pageText = page.string {
                        fullText += pageText
                        if pageIndex < pageCount - 1 {
                            fullText += "\n\n"
                        }
                    }

                    // Render page as image (only for first 10 pages)
                    if pageIndex < maxPagesForImages {
                        if let image = renderPageAsImage(page: page) {
                            pageImages.append(image)
                        }
                    }
                }
            }

            return PDFContent(
                url: url,
                text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                pageImages: pageImages,
                pageCount: pageCount
            )
        }

        private func renderPageAsImage(page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
            let pageRect = page.bounds(for: .mediaBox)
            let scaledSize = CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            )

            // Limit max size to prevent memory issues
            let maxDimension: CGFloat = 1500
            var finalScale = scale
            if scaledSize.width > maxDimension || scaledSize.height > maxDimension {
                let widthRatio = maxDimension / scaledSize.width
                let heightRatio = maxDimension / scaledSize.height
                finalScale = scale * min(widthRatio, heightRatio)
            }

            let finalSize = CGSize(
                width: pageRect.width * finalScale,
                height: pageRect.height * finalScale
            )

            let renderer = UIGraphicsImageRenderer(size: finalSize)
            let image = renderer.image { context in
                // White background
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: finalSize))

                // Transform for PDF coordinate system
                context.cgContext.translateBy(x: 0, y: finalSize.height)
                context.cgContext.scaleBy(x: finalScale, y: -finalScale)

                // Draw the PDF page
                page.draw(with: .mediaBox, to: context.cgContext)
            }

            return image
        }
    }
}
