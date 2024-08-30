//
//  RichTextEditor.swift
//  RichTextKitForAttributedString
//
//  Created by Joseph Levy on 7/29/24.
//
import SwiftUI

struct RichTextEditor: UIViewRepresentable {
	@Binding var attributedText: AttributedString
	@Binding var alignment: TextAlignment
	@State private var toolbar = KeyboardToolbar(textView: RichTextView())
	var textView: RichTextView { toolbar.textView } // created with toolbar above
	
	func makeUIView(context: Context) -> UITextView {
		textView.accessoryView = KeyboardAccessoryView(toolbar: $toolbar)
		textView.textContainerInset = UIEdgeInsets.zero
		textView.textContainer.lineFragmentPadding = 0
		textView.allowsEditingTextAttributes = true
		textView.delegate = context.coordinator
		textView.isEditable = true
		textView.textColor = .label
		
		textView.backgroundColor = .clear
		textView.textAlignment = switch alignment {case .leading: .left; case .center: .center; case .trailing: .right}
		textView.typingAttributes[.font] = UIFont.preferredFont(forTextStyle: .body)
		let accessoryViewController = UIHostingController(rootView: textView.accessoryView)
		textView.inputAccessoryView = {
			let accessoryView = accessoryViewController.view
			if let accessoryView {
				let frameSize = CGRect(x: 0, y: 0, width: 100, height: 44)
				accessoryView.frame = frameSize }
			return accessoryView
		}()
		
		return textView
	}
	
	func updateUIView(_ uiView: UITextView, context: Context) {
		uiView.textStorage.setAttributedString(attributedText.nsAttributedString())
		uiView.textAlignment = switch alignment {case .leading: .left; case .center: .center; case .trailing: .right}
		print("update UITextView")
	}
	
	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}
	
	class Coordinator: NSObject, UITextViewDelegate {
		var parent: RichTextEditor
		
		init(_ parent: RichTextEditor) {
			self.parent = parent
		}
		
		func textViewDidChange(_ textView: UITextView) {
//			if textView.attributedText.string != parent.placeholder {
				parent.attributedText =  textView.attributedText.attributedStringFromUIKit
//			}
			print("text did change")
			parent.alignment = textView.textAlignment.textAlignment
		}
	}
}

class RichTextView: UITextView, ObservableObject {
	public var accessoryView: KeyboardAccessoryView?
}
