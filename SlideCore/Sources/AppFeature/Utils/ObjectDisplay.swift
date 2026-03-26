import Foundation
@preconcurrency import SlideDatabase

// MARK: - Display helpers for TaskObject (OBXObject)

extension TaskObject {
    public var displayTitle: String {
        let base = payload.displayTitle
        if base.isEmpty {
            return kindSubtitle
        }
        return base
    }

    public var kindEmoji: String { payload.kindEmoji }
    public var kindSubtitle: String { payload.kindSubtitle }
}
