import Foundation
@preconcurrency import SlideDatabase

// MARK: - Display helpers for TaskObject (OBXObject)

extension TaskObject {
    public var displayTitle: String {
        if !customName.isEmpty { return customName }
        if !displayName.isEmpty { return displayName }
        return payload.kindSubtitle
    }

    public var kindEmoji: String { payload.kindEmoji }
    public var kindSubtitle: String { payload.kindSubtitle }
}
