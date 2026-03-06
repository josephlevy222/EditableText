//
//  EditableText.swift
//
//  Created by Joseph Levy on 7/16/24.
//  Modified 7/28/24
//  macCatalyst: MacFormattingToolbar shown above editor when focused.
//  Shares the KeyboardToolbar / RichTextView owned by RichTextEditor via a
//  @State toolbar that is passed into both views.
//

import SwiftUI

public struct EditableText: View {
	@Binding public var text: AttributedString
	@FocusState private var focus: Bool
	@State private var alignment: TextAlignment
	// Single toolbar instance shared between MacFormattingToolbar and RichTextEditor.
	// RichTextView is created here so both views reference the same underlying text view.
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
						MacFormattingToolbar(toolbar: $toolbar)
							.transition(.opacity)
					}
					#endif
					RichTextEditor(attributedText: $text, alignment: $alignment,
								   toolbar: $toolbar)
						.focused($focus)
						.opacity(focus ? 1 : 0)
				}
			}
	}
}

// MARK: - macCatalyst Formatting Toolbar

#if targetEnvironment(macCatalyst)
/// Native Mac toolbar that directly calls KeyboardAccessoryView's formatting methods,
/// using the shared KeyboardToolbar (and its RichTextView) passed in as a binding.
/// Only shows formatting-relevant controls — no speaker toggle, no dismiss-keyboard button.
private struct MacFormattingToolbar: View {
	@Binding var toolbar: KeyboardToolbar

	// A transient KeyboardAccessoryView that shares our toolbar binding.
	// We use it only as a method-call target, never rendering it directly.
	private var accessory: KeyboardAccessoryView { KeyboardAccessoryView(toolbar: $toolbar) }

	private let buttonSize: CGFloat = 28

	var body: some View {
		HStack(spacing: 2) {
			// Bold / Italic / Underline / Strikethrough
			Group {
				toolbarButton("bold",          highlighted: toolbar.isBold)          { accessory.toggleBoldface() }
				toolbarButton("italic",        highlighted: toolbar.isItalic)        { accessory.toggleItalics() }
				toolbarButton("underline",     highlighted: toolbar.isUnderline)     { accessory.toggleUnderline() }
				toolbarButton("strikethrough", highlighted: toolbar.isStrikethrough) { accessory.toggleStrikethrough() }
			}

			Divider().frame(height: 18).padding(.horizontal, 2)

			// Super / Subscript
			Group {
				toolbarButton("textformat.superscript", highlighted: toolbar.isSuperscript) { accessory.toggleSuperscript() }
				toolbarButton("textformat.subscript",   highlighted: toolbar.isSubscript)   { accessory.toggleSubscript() }
			}

			Divider().frame(height: 18).padding(.horizontal, 2)

			// Font size
			Button(action: { accessory.decreaseFontSize() }) {
				Image(systemName: "minus.circle")
			}
			.buttonStyle(.plain)
			Text(String(format: "%.1f", toolbar.fontSize))
				.font(.body.monospacedDigit())
				.frame(minWidth: 38, alignment: .center)
			Button(action: { accessory.increaseFontSize() }) {
				Image(systemName: "plus.circle")
			}
			.buttonStyle(.plain)

			Divider().frame(height: 18).padding(.horizontal, 2)

			// Text alignment
			Button(action: { accessory.alignText() }) {
				Image(systemName: toolbar.textAlignment.imageName)
			}
			.buttonStyle(.plain)
			.frame(width: buttonSize, height: buttonSize)

			Divider().frame(height: 18).padding(.horizontal, 2)

			// Color pickers
			ColorPicker("", selection: $toolbar.color, supportsOpacity: true)
				.labelsHidden()
				.onChange(of: toolbar.color) {  _ in accessory.selectColor() }
			ColorPicker("", selection: $toolbar.background, supportsOpacity: true)
				.labelsHidden()
				.onChange(of: toolbar.background) { _ in accessory.selectBackground() }

			Spacer()
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.frame(height: 36)
		.background(.bar)
	}

	private func toolbarButton(_ systemImage: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: systemImage)
				.frame(width: buttonSize, height: buttonSize)
				.background(
					RoundedRectangle(cornerRadius: 5)
						.fill(highlighted ? Color(UIColor.separator) : Color.clear)
				)
		}
		.buttonStyle(.plain)
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
