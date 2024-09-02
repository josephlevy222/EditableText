//
//  EditableText.swift
//
//  Created by Joseph Levy on 7/16/24.
//  Modified 7/28/24
//

import SwiftUI

public struct EditableText: View {
	@Binding public var text: AttributedString
	@FocusState private var focus : Bool
	@State private var alignment: TextAlignment  // can have more global UITextView paramters
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
				RichTextEditor(attributedText: $text, alignment: $alignment)
					.focused($focus)
					.opacity(focus ? 1 : 0)
			}
	}
}

public struct EditableTextInPopover: View {
	@Binding public var text: AttributedString
	@State private var alignment: TextAlignment  // can have more global UITextView paramters
	public init(_ text: Binding<AttributedString>, alignment: TextAlignment = .center) {
		_text = text
		_alignment = State(initialValue: alignment)
	}
	@State private var edit = false
	public var body: some View {
		Text(text)
			.multilineTextAlignment(alignment)
			.onTapGesture { edit = true }
			.popover(isPresented: $edit) {
				popView(text: $text, alignment: $alignment)
			}
	}
	
	struct popView: View {
		@Binding var text: AttributedString
		@Binding var alignment :TextAlignment
		@FocusState private var focus: Bool
		
		var body: some View {
			Text(text)
				.multilineTextAlignment(alignment)
				.onAppear { focus = true }
				.opacity(0)
				.background {
					RichTextEditor(attributedText: $text, alignment: $alignment)
						.focused($focus)
				}
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
					.border(Color.green.opacity(0.5))
				EditableTextInPopover($text)
					.fixedSize(horizontal: fixed, vertical: fixed)
					.border(Color.green.opacity(0.5))
				Toggle(isOn: $fixed) {  Text("Fixed") }.fixedSize()
				Button("Done") {
					UIApplication.shared
						.sendAction(#selector(UIResponder.resignFirstResponder),
									to: nil, from: nil, for: nil)
				}
				Button("Reset") { text = AttributedString("Reset of Type here...") }
			}
		}
	}
	return Preview()
}
