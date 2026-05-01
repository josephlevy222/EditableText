//
//  EditableText.swift
//
//  iOS 15+ compatible. No @Observable, no two-argument onChange.
//
//  GeometryReader in the overlay reads the actual laid-out size after SwiftUI has applied any external .frame() — so no need
//  to shadow the frame modifiers or store proposedWidth/proposedHeight.
//

import SwiftUI

// MARK: - EditableText (in-place editing)
public struct EditableText: View {
    @Binding public var text: AttributedString
    @FocusState private var focus: Bool
    @State private var alignment: TextAlignment
    @State private var toolbar: KeyboardToolbar
    var isPopover:       Bool   = false
    var placeholder:     String = " "
	@State private var edit = false
	@State private var keyboardShown = false
	
    public init(_ text: Binding<AttributedString>,
				alignment: TextAlignment = .center,
                placeholder: String = "Text",
                isPopover: Bool = false) {
        _text = text
		self.alignment = alignment
        _toolbar = State(initialValue: KeyboardToolbar(textView: RichTextView()))
        self.placeholder = placeholder.isEmpty ? " " : placeholder
        self.isPopover = isPopover
    }
	// Access the singleton directly
	@ObservedObject private var registry = FieldRegistry.shared
	@State private var fieldID = UUID().uuidString
    // MARK: - Body
    public var body: some View {
		Text(text.characters.isEmpty ? AttributedString(placeholder, font: .body) : text)
			.foregroundStyle(text.characters.isEmpty ? Color(.placeholderText) : Color(.label) )
			.multilineTextAlignment(alignment)
			.contentShape(Rectangle())
			.opacity(focus ? 0 : 1)
			.id(fieldID) // The anchor
			.onTapGesture {
				registry.activeID = fieldID // Mark focus in singleton
				focus = true
				if isPopover {
					#if targetEnvironment(macCatalyst)
						edit = true 
					#else
						if keyboardShown {  edit = true }
						else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { edit = true } }
					#endif
				}
			}
		
			.overlay {
				GeometryReader { g in
					// g.size reflects the idealSize of the Text.  I add 10 to the width in the popover to prevent wrapping
					// that is removed quickly on continued typing.  The side effect is there is sometimes no wrapping in the
					// popover when it is in the Text
					if isPopover {
						Color.clear.popover(isPresented: $edit) {
							RichTextEditor(attributedText: $text, alignment: $alignment, isEditing: true, toolbar: $toolbar,
										   proposedWidth:  g.size.width+10, proposedHeight: g.size.height)
							{ $0.becomeFirstResponder()  }
								.padding()
                                 #if !targetEnvironment(macCatalyst)
								.onReceive(keyboardPublisher) { shows in
									keyboardShown = shows
									if !shows { edit = false; focus = false }
								}
                                #endif
								.focused($focus)
						}
					}
					else {
						RichTextEditor(attributedText: $text, alignment: $alignment, isEditing: true, toolbar: $toolbar,
									   proposedWidth: g.size.width + 1, proposedHeight: g.size.height )
						.registerField()
//						.focused($focus)
//						.onChange(of: focus) { isFocused in
//							if !isFocused && FieldRegistry.shared.activeID == fieldID {
//								FieldRegistry.shared.activeID = nil
//								print("View Lost Focus: Registry cleared.")
//							}
//						}
						.opacity(focus ? 1 : 0)
					}
				}
			}
	}
}
