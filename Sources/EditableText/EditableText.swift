//
//  EditableText.swift
//
//  Created by Joseph Levy on 7/16/24.
//  Modified 7/28/24
//

import SwiftUI

struct EditableText: View {
	@Binding public var text: AttributedString
	@FocusState private var focus : Bool
	@State private var alignment: TextAlignment  // can have more global UITextView paramters
	public init(_ text: Binding<AttributedString>, alignment: TextAlignment = .center) {
		_text = text
		_alignment = State(initialValue: alignment)
	}
	var body: some View {
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

#Preview {
	struct Preview: View {
		@State var text = AttributedString("Type here...")
		@State var fixed = false
		var body: some View {
			VStack {
				EditableText($text)
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
