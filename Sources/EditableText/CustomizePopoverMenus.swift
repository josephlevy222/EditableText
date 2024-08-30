//
//  CustomizePopoverMenus.swift
//  RichTextKitForAttributedString
//
//  Created by Joseph Levy on 7/26/24.
//

import SwiftUI

extension RichTextView {
	var toolbar: Binding<KeyboardToolbar>? { accessoryView?.$toolbar }
	
	open override func canPerformAction(_ action: Selector, withSender sender: Any? ) -> Bool {
		if action.description.contains("_share")
			|| action.description.contains("_translate")
			|| action.description.contains("_define")
			//|| action.description.contains("_showTextStyleOptions") // BIU
			{ return false }
		return super.canPerformAction(action, withSender: sender)
	}
	
	open override func buildMenu(with builder: UIMenuBuilder) {
		builder.remove(menu: .lookup)
		builder.remove(menu: .share)
		//builder.remove(menu: .textStyle)
		super.buildMenu(with: builder)
	}
	
	/// Make this work with undo/redo
	public func updateAttributedText(with attributedString: NSAttributedString) {
		attributedText = attributedString
		if let update = delegate?.textViewDidChange {
			update(self) }
	}
	
	// Override the system calls for textView updates
	@objc open override func toggleBoldface(_ sender: Any?) {
		accessoryView?.toggleBoldface() ??
		super.toggleBoldface(sender)
	}
	@objc open override func toggleItalics(_ sender: Any?) {
		accessoryView?.toggleItalics() ??
		super.toggleItalics(sender)
	}
	@objc open override func toggleUnderline(_ sender: Any?) {
		accessoryView?.toggleUnderline() ??
		super.toggleUnderline(sender)
	}
	
}

