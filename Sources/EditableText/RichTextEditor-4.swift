//
//  RichTextEditor.swift
//  RichTextKitForAttributedString
//
//  Created by Joseph Levy on 7/29/24.
//
import SwiftUI

public struct RichTextEditor: UIViewRepresentable {
	public init(attributedText: Binding<AttributedString>, alignment: Binding<TextAlignment>,
				toolbar: Binding<KeyboardToolbar>? = nil,
				configuration: @escaping (UITextView) -> () = { _ in }) {
		_attributedText = attributedText
		_alignment = alignment
		_toolbar = toolbar ?? .constant(KeyboardToolbar(textView: RichTextView()))
		configure = configuration
	}
	@Binding var attributedText: AttributedString
	@Binding var alignment: TextAlignment
	// toolbar (and its embedded RichTextView) may be owned here or passed in from
	// EditableText so that MacFormattingToolbar shares the same instance on macCatalyst.
	@Binding private var toolbar: KeyboardToolbar
	public var configure = { (view: UITextView) in }

	var textView: RichTextView { toolbar.textView }

	public func makeUIView(context: Context) -> UITextView {
		// Always create accessoryView so richTextView?.toolbar resolves on all
		// platforms — KeyboardAccessoryView.textViewDidChangeSelection needs it
		// to push font/bold/italic state back into the toolbar binding.
		textView.accessoryView = KeyboardAccessoryView(toolbar: $toolbar)
		#if !targetEnvironment(macCatalyst)
		// On iOS wire up the input accessory bar above the keyboard.
		let accessoryViewController = UIHostingController(rootView: textView.accessoryView!)
		textView.inputAccessoryView = {
			let accessoryView = accessoryViewController.view
			if let accessoryView {
				accessoryView.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
			}
			return accessoryView
		}()
		#endif

		textView.textContainerInset = UIEdgeInsets.zero
		textView.textContainer.lineFragmentPadding = 0
		textView.allowsEditingTextAttributes = true
		textView.delegate = context.coordinator
		textView.isEditable = true
		textView.textColor = .label
		textView.backgroundColor = .clear
		textView.textAlignment = switch alignment {case .leading: .left; case .center: .center; case .trailing: .right}
		textView.typingAttributes[.font] = UIFont.preferredFont(forTextStyle: .body)
		DispatchQueue.main.async { attributedText = attributedText.nsAttributedString().attributedStringFromUIKit }
		configure(textView)
		return textView
	}

	public func updateUIView(_ uiView: UITextView, context: Context) {
		uiView.textStorage.setAttributedString(attributedText.nsAttributedString())
		uiView.textAlignment = switch alignment {case .leading: .left; case .center: .center; case .trailing: .right}
	}

	public func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	public class Coordinator: NSObject, UITextViewDelegate {
		var parent: RichTextEditor

		init(_ parent: RichTextEditor) {
			self.parent = parent
		}

		public func textViewDidChange(_ textView: UITextView) {
			parent.attributedText = textView.attributedText.attributedStringFromUIKit
			parent.alignment = textView.textAlignment.textAlignment
		}

		/// Forward selection changes to KeyboardAccessoryView's coordinator so it
		/// can update toolbar state (font size, bold, italic, etc.) on all platforms
		/// including macCatalyst where there is no keyboard accessory bar.
		public func textViewDidChangeSelection(_ textView: UITextView) {
			guard let richTextView = textView as? RichTextView,
				  let accessoryCoordinator = richTextView.accessoryView?.coordinator
			else { return }
			accessoryCoordinator.textViewDidChangeSelection(textView)
		}
	}
}

class RichTextView: UITextView, ObservableObject {
	public var accessoryView: KeyboardAccessoryView?
}
