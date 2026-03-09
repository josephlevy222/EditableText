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
		// Always set accessoryView (our custom property) so richTextView?.toolbar
		// resolves on all platforms — textViewDidChangeSelection needs it to push
		// font/bold/italic state back into the toolbar binding.
		textView.accessoryView = KeyboardAccessoryView(toolbar: $toolbar)
		#if !targetEnvironment(macCatalyst)
		// On iOS only: wire up the formatting bar above the software keyboard.
		// Do NOT do this on macCatalyst — there is no software keyboard, and
		// attaching inputAccessoryView interferes with NumericTextField focus.
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
		textView.isSelectable = true
		textView.isScrollEnabled = false
		textView.contentInsetAdjustmentBehavior = .never
		textView.textColor = .label
		textView.tintColor = .tintColor
#if targetEnvironment(macCatalyst)
		// On macCatalyst, UITextView bridges to NSTextView which cannot draw
		// selection highlights over a .clear background — the selection becomes
		// invisible and artifacts appear. Use .systemBackground (adaptive
		// light/dark) so the selection renders correctly.
		textView.backgroundColor = .systemBackground
#else
		textView.backgroundColor = .clear
#endif
		textView.textAlignment = switch alignment {case .leading: .left; case .center: .center; case .trailing: .right}
		textView.typingAttributes[.font] = UIFont.preferredFont(forTextStyle: .body)
		DispatchQueue.main.async { attributedText = attributedText.nsAttributedString().attributedStringFromUIKit }
		configure(textView)
		return textView
	}

	public func updateUIView(_ uiView: UITextView, context: Context) {
		// Never replace textStorage while the view is first responder — doing so
		// clears the selection and kills the highlight. The user is actively editing;
		// textViewDidChange keeps attributedText in sync in that direction already.
		if !uiView.isFirstResponder {
			let incoming = attributedText.nsAttributedString()
			if !uiView.attributedText.isEqual(to: incoming) {
				uiView.textStorage.setAttributedString(incoming)
			}
		}
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

	}
}

class RichTextView: UITextView, ObservableObject {
	public var accessoryView: KeyboardAccessoryView?
}
