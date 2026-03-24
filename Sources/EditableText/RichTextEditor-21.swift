//
//  RichTextEditor.swift
//
//  UIViewRepresentable wrapping RichTextView.
//  - iOS iPad:  full KeyboardAccessoryView as inputAccessoryView
//  - iOS iPhone: CompactKeyboardAccessoryView (two-line) as inputAccessoryView
//  - macCatalyst: no inputAccessoryView; formatting via menu bar
//
//  proposedWidth/proposedHeight: when set, constrain the UITextView's textContainer directly.
//  When nil, UIKit manages layout from view bounds.
//
//  scrollingHeight on RichTextView decouples intrinsicContentSize (fixed frame height)
//  from textContainer.size (free height for full layout) when isScrollEnabled.
//

import SwiftUI

public struct RichTextEditor: UIViewRepresentable {
    public init(attributedText: Binding<AttributedString>,
                alignment: Binding<TextAlignment>,
                isEditing: Bool = true,
                toolbar: Binding<KeyboardToolbar>? = nil,
                proposedWidth: CGFloat? = nil,
                proposedHeight: CGFloat? = nil,
                configuration: @escaping (UITextView) -> Void = { _ in }) {
        _attributedText = attributedText
        _alignment = alignment
        self.isEditing = isEditing
        _toolbar = toolbar ?? .constant(KeyboardToolbar(textView: RichTextView()))
        self.proposedWidth = proposedWidth
        self.proposedHeight = proposedHeight
        configure = configuration
    }

    @Binding var attributedText: AttributedString
    @Binding var alignment: TextAlignment
    var isEditing: Bool
    @Binding private var toolbar: KeyboardToolbar
    var proposedWidth: CGFloat?
    var proposedHeight: CGFloat?
    public var configure: (UITextView) -> Void

    var textView: RichTextView { toolbar.textView }

    public func makeUIView(context: Context) -> UITextView {
        textView.isScrollEnabled                   = false
        textView.backgroundColor                   = .clear
        textView.textContainerInset                = .zero
        textView.contentOffset                     = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.allowsEditingTextAttributes       = true
        textView.delegate                          = context.coordinator
        textView.attributedText                    = attributedText.nsAttributedString()
        textView.tintColor                         = .tintColor
        textView.textAlignment                     = switch alignment {
            case .center: .center; case .leading: .left; case .trailing: .right
        }
        textView.isEditable                        = isEditing
        textView.isSelectable                      = isEditing
        textView.textColor                         = .label
        textView.typingAttributes[.font]           = UIFont.preferredFont(forTextStyle: .body)
        textView.toolbar                           = $toolbar
        textView.contentInsetAdjustmentBehavior    = .never

        applyContainerSize(to: textView)
        textView.invalidateIntrinsicContentSize()

        #if !targetEnvironment(macCatalyst)
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let accessoryHeight: CGFloat = isIPad ? 44 : 80
        let accessoryContent: AnyView = isIPad
            ? AnyView(KeyboardAccessoryView(toolbar: $toolbar))
            : AnyView(CompactKeyboardAccessoryView(toolbar: $toolbar))
        let host = UIHostingController(rootView: accessoryContent)
        host.view.backgroundColor = UIColor.systemGroupedBackground
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: accessoryHeight)
        host.view.autoresizingMask = [.flexibleWidth]
        textView.inputAccessoryView = host.view
        textView.inputAccessoryHost = host
        #endif

        DispatchQueue.main.async {
            attributedText = attributedText.nsAttributedString().attributedStringFromUIKit
        }
        configure(textView)
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        // Don't replace text storage while first responder — textViewDidChange
        // already syncs in that direction, and setAttributedString resets contentOffset.
        if !uiView.isFirstResponder {
            let incoming = attributedText.nsAttributedString()
            if !uiView.attributedText.isEqual(to: incoming) {
                uiView.textStorage.setAttributedString(incoming)
            }
			forceCatalystLayout(to: uiView)
		} else {
			// beep
		}

        uiView.textAlignment = switch alignment {
            case .leading: .left; case .center: .center; case .trailing: .right
        }

        applyContainerSize(to: uiView)
        uiView.invalidateIntrinsicContentSize()

        // Scroll to keep cursor visible in fixed height container
        if uiView.isFirstResponder && uiView.isScrollEnabled {
            DispatchQueue.main.async {
                if let selectedRange = uiView.selectedTextRange {
                    let cursorRect    = uiView.caretRect(for: selectedRange.end)
                    let cursorBottom  = cursorRect.maxY
                    let cursorTop     = cursorRect.minY
                    let visibleBottom = uiView.contentOffset.y + uiView.bounds.height
                    let visibleTop    = uiView.contentOffset.y
                    if cursorBottom > visibleBottom {
                        uiView.contentOffset = CGPoint(
                            x: 0,
                            y: min(cursorBottom - uiView.bounds.height,
                                   uiView.contentSize.height - uiView.bounds.height)
                        )
                    } else if cursorTop < visibleTop {
                        uiView.contentOffset = CGPoint(x: 0, y: cursorTop)
                    }
                }
            }
        }

        #if !targetEnvironment(macCatalyst)
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        if let tv = uiView as? RichTextView {
            tv.inputAccessoryHost?.rootView = isIPad
                ? AnyView(KeyboardAccessoryView(toolbar: $toolbar))
                : AnyView(CompactKeyboardAccessoryView(toolbar: $toolbar))
        }
        #endif
    }

    // MARK: - Container size

	private func applyContainerSize(to uiView: UITextView) {
		let free = CGFloat.greatestFiniteMagnitude
		let w = proposedWidth  ?? free
		let h = proposedHeight ?? free
		let scrolling = h != free
		if let tv = uiView as? RichTextView {
			tv.scrollingHeight = scrolling ? h : nil
		}
		let containerSize = CGSize(width: w, height: scrolling ? free : h)
		if uiView.textContainer.size != containerSize {
			uiView.textContainer.size = containerSize
			uiView.isScrollEnabled    = scrolling
			forceCatalystLayout(to: uiView)
			uiView.invalidateIntrinsicContentSize()
		}
	}
	
	private func forceCatalystLayout(to uiView: UITextView) {
#if targetEnvironment(macCatalyst)
		/// macCatalyst doesn't re-flow text when textContainer.size changes while first responder. Force re-flow by simulating a no-op text edit.
		/// Collapses selection first to avoid deleting selected text. Shuts off undo/redo while insert-delete occur.
		if uiView.isFirstResponder {
			DispatchQueue.main.async {
				print("In hack")
				let savedRange = uiView.selectedRange
				uiView.selectedRange = NSRange(location: savedRange.location, length: 0)
				uiView.undoManager?.disableUndoRegistration()
				uiView.insertText(" ")
				uiView.deleteBackward()
				uiView.undoManager?.enableUndoRegistration()
				uiView.selectedRange = savedRange
			}
		}
#endif
	}
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

        public func textViewDidChange(_ textView: UITextView) {
            parent.attributedText = textView.attributedText.attributedStringFromUIKit
            parent.alignment      = textView.textAlignment.textAlignment
            updateToolbarState(for: textView)
            textView.invalidateIntrinsicContentSize()
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.alignment = textView.textAlignment.textAlignment
                self.updateToolbarState(for: textView)
            }
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            parent.alignment = textView.textAlignment.textAlignment
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            textView.textAlignment = switch self.parent.alignment {
                case .leading: .left; case .center: .center; case .trailing: .right
            }
            textView.contentOffset = .zero
            textView.invalidateIntrinsicContentSize()
			parent.forceCatalystLayout(to: textView)
        }
    }
}

// MARK: - RichTextView

class RichTextView: UITextView {
    /// Retained hosting controller for the inputAccessoryView (iOS only)
    var inputAccessoryHost: UIHostingController<AnyView>?

    /// Toolbar binding — set by RichTextEditor.makeUIView so the Coordinator and CustomizePopoverMenus can reach it.
    var toolbar: Binding<KeyboardToolbar>?

    /// Fixed frame height reported to SwiftUI when isScrollEnabled = true.  Decouples intrinsicContentSize from textContainer.size
	/// so the view stays at the frame height while text lays out at full height for scrolling.
    var scrollingHeight: CGFloat? = nil

    override var intrinsicContentSize: CGSize {
        let free = CGFloat.greatestFiniteMagnitude
        let w = textContainer.size.width
        let h = textContainer.size.height

        // Scrolling — textContainer height is free but SwiftUI view is fixed
        if let sh = scrollingHeight, isScrollEnabled {
            let naturalWidth = w == free
                ? sizeThatFits(CGSize(width: free, height: free)).width
                : w
            return CGSize(width: naturalWidth, height: sh)
        }

        guard w != free || h != free else {
            let s = super.intrinsicContentSize
            guard s.width < free && s.height < free else {
                return CGSize(width: UIView.noIntrinsicMetric,
                              height: UIView.noIntrinsicMetric)
            }
            return s
        }

        switch (w == free, h == free) {
        case (false, true):   // fixed width, grow vertically
            return sizeThatFits(CGSize(width: w, height: free))
        case (true, false):   // fixed height, grow horizontally
            return CGSize(width: sizeThatFits(CGSize(width: free, height: h)).width, height: h)
        case (false, false):  // both fixed — UITextView scrolls internally
            return CGSize(width: w, height: h)
        default:
            return super.intrinsicContentSize
        }
    }

    func updateAttributedText(with attributedString: NSAttributedString) {
        attributedText = attributedString
        if let update = delegate?.textViewDidChange { update(self) }
    }
}
