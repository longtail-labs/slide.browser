import AppKit
import SwiftUI

// MARK: - Color Extension

public extension Color {
	//    static let slideAccent = Color(hex: 0x8524F5)
	static let slideAccent = Color("AccentColor")

	init(hex: UInt, alpha: Double = 1) {
		self.init(
			.sRGB,
			red: Double((hex >> 16) & 0xff) / 255,
			green: Double((hex >> 08) & 0xff) / 255,
			blue: Double((hex >> 00) & 0xff) / 255,
			opacity: alpha
		)
	}
}

// MARK: - Pointer Hand Cursor Modifier

struct PointerHandCursor: ViewModifier {
	@Environment(\.cursorInteractionsEnabled) private var cursorInteractionsEnabled
	@State private var isHovering = false

	func body(content: Content) -> some View {
		content
			.onHover { hovering in
				guard cursorInteractionsEnabled else { return }
				isHovering = hovering
				if hovering {
					// Use cursor stack for safe overrides
					NSCursor.pointingHand.push()
				} else {
					NSCursor.pop()
				}
			}
	}
}

public extension View {
	func pointerHandCursor() -> some View {
		self.modifier(PointerHandCursor())
	}
}

// MARK: - Conditional Hidden Helper

public extension View {
	@ViewBuilder
	func hidden(_ shouldHide: Bool) -> some View {
		if shouldHide { self.hidden() } else { self }
	}
}

// MARK: - Cursor Interactions Environment Key

private struct CursorInteractionsEnabledKey: EnvironmentKey {
	static let defaultValue: Bool = true
}

public extension EnvironmentValues {
	var cursorInteractionsEnabled: Bool {
		get { self[CursorInteractionsEnabledKey.self] }
		set { self[CursorInteractionsEnabledKey.self] = newValue }
	}
}
