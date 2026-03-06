//
//  EditableText.swift
//
//  Created by Joseph Levy on 7/16/24.
//  Modified 7/28/24
//  macCatalyst toolbar added: shows a formatting bar above the editor when focused,
//  since inputAccessoryView is keyboard-only and has no effect on Mac.
//

import SwiftUI

public struct EditableText: View {
	@Binding public var text: AttributedString
	@FocusState private var focus: Bool
	@State private var alignment: TextAlignment
	@State private var toolbar = KeyboardToolbar(textView: RichTextView())

	public init(_ text: Binding<AttributedString>, alignment: TextAlignment = .center) {
		_text = text
		_alignment = State(initialValue: alignment)
	}

	public var body: some View {
		Text(text)
			.multilineTextAlignment(alignment)
			.opacity(focus ? 0 : 1)
			.onTapGesture { focus = true }
			.overlay {
				VStack(spacing: 0) {
					#if targetEnvironment(macCatalyst)
					if focus {
						MacFormattingToolbar(accessoryView: KeyboardAccessoryView(toolbar: $toolbar))
							.frame(height: 44)
							.transition(.opacity)
					}
					#endif
					RichTextEditor(attributedText: $text, alignment: $alignment)
						.focused($focus)
						.opacity(focus ? 1 : 0)
				}
			}
	}
}

// MARK: - macCatalyst Formatting Toolbar

#if targetEnvironment(macCatalyst)
/// A SwiftUI toolbar that mirrors the iOS keyboard accessory bar for macCatalyst.
/// It wraps `KeyboardAccessoryView` directly so all formatting logic is shared — no duplication.
struct MacFormattingToolbar: View {
	/// We hold the `KeyboardAccessoryView` by value so it has access to the same `toolbar` binding
	/// and `textView` reference that the underlying `RichTextEditor` uses.
	var accessoryView: KeyboardAccessoryView

	var body: some View {
		accessoryView
			.background(.bar)                      // native macOS toolbar material
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.shadow(color: .black.opacity(0.08), radius: 4, y: 2)
			.padding(.horizontal, 4)
			.padding(.bottom, 2)
	}
}
#endif

// MARK: - EditableTextInPopover (unchanged)

public struct EditableTextInPopover: View {
	@Binding public var text: AttributedString
	@State private var alignment: TextAlignment
	public init(_ text: Binding<AttributedString>, alignment: TextAlignment = .center) {
		_text = text
		_alignment = State(initialValue: alignment)
	}
	@State private var edit = false
	@FocusState private var focus: Bool
	@FocusState private var popFocus: Bool
	@State private var keyboardShown: Bool = false
	@Environment(\.dismiss) private var dismiss
	public var body: some View {
		Text(text)
			.multilineTextAlignment(alignment)
			.onTapGesture {
				withAnimation {
					if keyboardShown { edit = true }
					else { focus = true }
				}
			}
			.background {
				RichTextEditor(attributedText: $text, alignment: $alignment)
					.focused($focus)
					.opacity(0)
			}
			.popover(isPresented: $edit) {
				Text(text)
					.multilineTextAlignment(alignment)
					.opacity(0)
					.overlay {
						RichTextEditor(attributedText: $text, alignment: $alignment) {
							if keyboardShown { $0.becomeFirstResponder() }
						}
					}
			}
			.onReceive(keyboardPublisher) { shows in
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
					keyboardShown = shows
				}
			}.onChange(of: keyboardShown) {
				if $0 { if focus { edit = true } }
				else { edit = false }
			}
	}
}

#Preview {
	struct Preview: View {
		@State var text = AttributedString("Type here...")
		@State var fixed = false
		var body: some View {
			VStack {
				EditableText($text)
					.fixedSize(horizontal: fixed, vertical: fixed)
					.debugFrame()
				Spacer()
				EditableTextInPopover($text)
					.fixedSize(horizontal: fixed, vertical: fixed)
					.debugFrame()
				Toggle(isOn: $fixed) { Text("Fixed") }.fixedSize()
				Button("Done") {
					UIApplication.shared
						.sendAction(#selector(UIResponder.resignFirstResponder),
									to: nil, from: nil, for: nil)
				}
				Button("Reset") { text = AttributedString("Reset of Type here...") }
				Spacer()
			}
		}
	}
	return Preview()
}
