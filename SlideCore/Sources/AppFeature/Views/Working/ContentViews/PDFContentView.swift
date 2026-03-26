import SwiftUI
import PDFKit
import SlideDatabase

struct PDFContentView: View {
    let object: TaskObject
    @State private var currentPage: Int = 1
    
    var body: some View {
        if let filePath = object.filePath {
            PDFKitRepresentable(url: filePath, currentPage: $currentPage)
                .background(Color(NSColor.textBackgroundColor))
        } else {
            VStack {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("PDF not found")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
    }
}

// Custom PDFView subclass to handle context menu
class CustomPDFView: PDFKit.PDFView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        
        // Remove any existing "Search with Google" items that PDFKit might provide
        var indicesToRemove: [Int] = []
        for (idx, item) in menu.items.enumerated().reversed() {
            let title = item.title.lowercased()
            if title.contains("search") && (title.contains("google") || title.contains("web")) {
                indicesToRemove.append(idx)
            }
        }
        
        // Remove the built-in search items
        for idx in indicesToRemove.sorted(by: >) {
            menu.removeItem(at: idx)
        }
        
        // Add our custom Save to Note item
        let saveToNoteItem = NSMenuItem(title: "Save Selection to Note", action: #selector(saveSelectionToNote), keyEquivalent: "")
        saveToNoteItem.target = self
        
        // Add our custom Search with Google item
        let searchWithGoogleItem = NSMenuItem(title: "Search with Google", action: #selector(searchWithGoogle), keyEquivalent: "")
        searchWithGoogleItem.target = self
        
        // Insert after the first separator or at the beginning
        if let firstSeparatorIndex = menu.items.firstIndex(where: { $0.isSeparatorItem }) {
            menu.insertItem(searchWithGoogleItem, at: firstSeparatorIndex + 1)
            menu.insertItem(saveToNoteItem, at: firstSeparatorIndex + 1)
        } else {
            menu.insertItem(searchWithGoogleItem, at: 0)
            menu.insertItem(saveToNoteItem, at: 0)
        }
        
        return menu
    }
    
    @objc private func saveSelectionToNote() {
        guard let selection = currentSelection?.string else { return }
        let trimmedText = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Post notification with the selected text
        NotificationCenter.default.post(
            name: Notification.Name("PDFSaveSelectionToNote"),
            object: nil,
            userInfo: ["text": trimmedText]
        )
    }
    
    @objc private func searchWithGoogle() {
        guard let selection = currentSelection?.string else { return }
        let trimmedText = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Post notification with the selected text
        NotificationCenter.default.post(
            name: Notification.Name("PDFSearchWithGoogle"),
            object: nil,
            userInfo: ["text": trimmedText]
        )
    }
}

struct PDFKitRepresentable: NSViewRepresentable {
    typealias NSViewType = CustomPDFView
    
    let url: URL
    @Binding var currentPage: Int
    
    func makeNSView(context: Context) -> CustomPDFView {
        let pdfView = CustomPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        // Set up notification observer for keyboard shortcut
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.triggerSaveSelection),
            name: Notification.Name("TriggerSaveSelectionPDF"),
            object: nil
        )
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            
            // Set up page change observer
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: pdfView
            )
        }
        
        context.coordinator.pdfView = pdfView
        return pdfView
    }
    
    func updateNSView(_ nsView: CustomPDFView, context: Context) {
        // Update current page if changed externally
        if let document = nsView.document,
           currentPage > 0,
           currentPage <= document.pageCount,
           let page = document.page(at: currentPage - 1),
           nsView.currentPage != page {
            nsView.go(to: page)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: PDFKitRepresentable
        weak var pdfView: CustomPDFView?
        
        init(_ parent: PDFKitRepresentable) {
            self.parent = parent
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFKit.PDFView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage else { return }
            
            let pageIndex = document.index(for: currentPage)
            parent.currentPage = pageIndex + 1
        }
        
        @objc func triggerSaveSelection() {
            guard let pdfView = pdfView,
                  let selection = pdfView.currentSelection?.string else { return }
            let trimmedText = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return }
            
            // Post notification with the selected text
            NotificationCenter.default.post(
                name: Notification.Name("PDFSaveSelectionToNote"),
                object: nil,
                userInfo: ["text": trimmedText]
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}