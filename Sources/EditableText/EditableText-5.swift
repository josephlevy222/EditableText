//
//  EditableText.swift
//
//  Created by Joseph Levy on 7/16/24.
//  Modified 7/28/24
//  macCatalyst: formatting handled by FormattingPalette (floating UIWindow).
//  iOS 15+ compatible: single-argument onChange, no @Observable.
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
				RichTextEditor(attributedText: $text, alignment: $alignment,
							   toolbar: $toolbar)
					.focused($focus)
					.opacity(focus ? 1 : 0)
			}
			.onChange(of: focus) { focused in
#if targetEnvironment(macCatalyst)
				if focused {
					FormattingPalette.shared.show(toolbar: $toolbar)
				} else {
					FormattingPalette.shared.detach()
				}
#endif
			}
	}
}

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
