import AppKit
import STTextView
import UniformTypeIdentifiers

/// STTextView subclass with image drag-drop support.
public final class SlideTextView: STTextView {
    /// Called when an image is dropped. Returns markdown string to insert, or nil.
    public var imageSaveHandler: ((Data, String) -> String?)?

    public override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        types.append(contentsOf: [.fileURL, .png, .tiff])
        return types
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if pasteboardContainsImage(sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if pasteboardContainsImage(sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard pasteboardContainsImage(pasteboard) else {
            return super.performDragOperation(sender)
        }
        guard let markdown = handleImagePasteboard(pasteboard) else { return false }
        insertText(markdown, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    // MARK: - Image detection

    private func pasteboardContainsImage(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL], !urls.isEmpty {
            return true
        }
        if pasteboard.string(forType: .string) != nil { return false }
        for type in [NSPasteboard.PasteboardType.tiff, .png] {
            if pasteboard.data(forType: type) != nil { return true }
        }
        return false
    }

    private func handleImagePasteboard(_ pasteboard: NSPasteboard) -> String? {
        // File URL images
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL], let url = urls.first {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let filename = url.lastPathComponent
            return imageSaveHandler?(data, filename)
        }
        // Raw image data (screenshot paste, etc.)
        if let tiffData = pasteboard.data(forType: .tiff) {
            let pngData = convertTIFFtoPNG(tiffData) ?? tiffData
            let filename = "image-\(UUID().uuidString.prefix(8)).png"
            return imageSaveHandler?(pngData, filename)
        }
        if let pngData = pasteboard.data(forType: .png) {
            let filename = "image-\(UUID().uuidString.prefix(8)).png"
            return imageSaveHandler?(pngData, filename)
        }
        return nil
    }

    private func convertTIFFtoPNG(_ tiffData: Data) -> Data? {
        guard let imageRep = NSBitmapImageRep(data: tiffData) else { return nil }
        return imageRep.representation(using: .png, properties: [:])
    }
}
