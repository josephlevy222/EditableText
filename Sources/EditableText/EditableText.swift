//
//  EditableText.swift
//
//  Created by Joseph Levy on 7/16/24.
//  Modified 7/28/24
//  macCatalyst: FormattingPalette (floating UIWindow) handles formatting.
//  EditableTextInPopover: on macCatalyst opens popover directly on tap
//  since there is no software keyboard to trigger the popover.
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

// MARK: - EditableTextInPopover

public struct EditableTextInPopover: View {
	@Binding public var text: AttributedString
	@State private var alignment: TextAlignment
	@State private var toolbar = KeyboardToolbar(textView: RichTextView())

	public init(_ text: Binding<AttributedString>, alignment: TextAlignment = .center) {
		_text = text
		_alignment = State(initialValue: alignment)
	}

	@State private var edit = false
	@FocusState private var focus: Bool
	@State private var keyboardShown: Bool = false
	@Environment(\.dismiss) private var dismiss

	public var body: some View {
		Text(text)
			.multilineTextAlignment(alignment)
			.onTapGesture {
				withAnimation {
#if targetEnvironment(macCatalyst)
					// No software keyboard on Mac — open the popover directly.
					edit = true
#else
					if keyboardShown { edit = true }
					else { focus = true }
#endif
				}
			}
#if !targetEnvironment(macCatalyst)
			// On Mac this hidden RichTextEditor is unnecessary — the popover
			// contains its own editor and there's no keyboard to wait for.
			.background {
				RichTextEditor(attributedText: $text, alignment: $alignment,
							   toolbar: $toolbar)
					.focused($focus)
					.opacity(0)
			}
#endif
			.popover(isPresented: $edit) {
				Text(text)
					.multilineTextAlignment(alignment)
					.opacity(0)
					.overlay {
						RichTextEditor(attributedText: $text, alignment: $alignment,
									   toolbar: $toolbar) {
#if !targetEnvironment(macCatalyst)
							if keyboardShown { $0.becomeFirstResponder() }
#else
							$0.becomeFirstResponder()
#endif
						}
					}
#if targetEnvironment(macCatalyst)
					// Wire the palette to the popover's toolbar while it's open.
					.onAppear { FormattingPalette.shared.show(toolbar: $toolbar) }
					.onDisappear { FormattingPalette.shared.detach() }
#endif
			}
#if !targetEnvironment(macCatalyst)
			.onReceive(keyboardPublisher) { shows in
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
					keyboardShown = shows
				}
			}
			.onChange(of: keyboardShown) {
				if $0 { if focus { edit = true } }
				else { edit = false }
			}
#endif
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
