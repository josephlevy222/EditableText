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
	@State private var latchEdit = false
	@FocusState private var focus : Bool
	@State var keyboardShown : Bool = false
	public var body: some View {
		ZStack {
			EditableText(.constant(AttributedString())).focused($focus)
			Text(text)
				.multilineTextAlignment(alignment)
				.popover(isPresented: $edit) {
					popView(text: $text, alignment: $alignment)
				}
		}.onTapGesture { print("tapped"); latchEdit = true
			if focus { edit = true; latchEdit = false } else { focus = true }
		}.onReceive(keyboardPublisher) { shows in print("keyboard \(shows)")
			keyboardShown = shows
		}.onChange(of: keyboardShown) { 
			if $0 {
				edit = latchEdit; latchEdit = false
			} else {
				focus = false; edit = false
			}
		}
	}
	
	struct popView: View {
		@Binding var text: AttributedString
		@Binding var alignment :TextAlignment
		//@FocusState private var focus: Bool
		@Environment(\.dismiss) var dismiss
		var body: some View {
			Text(text)
				.multilineTextAlignment(alignment)
				.opacity(0)
				.overlay {
					RichTextEditor(attributedText: $text, alignment: $alignment) {
						$0.becomeFirstResponder()
					}
					
						//.focused($focus).onChange(of: focus) { if !$0 {dismiss()}}
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
