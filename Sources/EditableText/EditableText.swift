//
//  EditableText.swift
//
//  Created by Joseph Levy on 7/16/24.
//  Modified 7/28/24
//

import SwiftUI

public struct EditableText: View {
	@Binding public var text: AttributedString
	@FocusState private var focus : Bool //= false
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
				RichTextEditor(attributedText: $text, alignment: $alignment)  {
					if focus { $0.becomeFirstResponder()}
				}
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
	@FocusState private var focus : Bool
	@State private var keyboardShown : Bool = false
	
	public var body: some View {
		ZStack {
			EditableText($text).focused($focus)
				.popover(isPresented: $edit) {
					popView(text: $text, alignment: $alignment)
				}
				.onTapGesture {
					if focus { edit = true }
				}
		}.onTapGesture {
			if keyboardShown { edit = true }
			else { focus = true }
		}.onChange(of: focus) {
			if $0 {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					edit = true // After 0.5 seconds the keyboard shows I hope
				}
			}
		}.onReceive(keyboardPublisher) { shows in print("keyboard \(shows)")
			keyboardShown = shows
			if !keyboardShown { edit = false }
		}
	}
	
	struct popView: View {
		@Binding var text: AttributedString
		@Binding var alignment :TextAlignment
		//var focus: Bool
		var body: some View {
			Text(text)
				.multilineTextAlignment(alignment)
				.opacity(0)
				.overlay {
					RichTextEditor(attributedText: $text, alignment: $alignment) {
						 $0.becomeFirstResponder() //when created or updated
					}
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
				Spacer()
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
				Spacer()
			}
		}
	}
	return Preview()
}
