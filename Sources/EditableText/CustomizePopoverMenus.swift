//
//  CustomizePopoverMenus.swift
//
//  - Removes share / translate / define from the callout bubble
//  - Adds Superscript and Subscript to the callout bubble (all platforms)
//  - Adds Superscript and Subscript to Format > Font in the Mac menu bar
//  - Bold / Italic / Underline left to system (UIResponder) on all platforms
//

import SwiftUI
import UIKit

extension RichTextView {

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleSuperscript(_:)) ||
           action == #selector(toggleSubscript(_:)) {
            return isEditable
        }
        if action.description.contains("_share")
            || action.description.contains("_translate")
            || action.description.contains("_define") {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    open override func buildMenu(with builder: UIMenuBuilder) {
        builder.remove(menu: .lookup)
        builder.remove(menu: .share)

        let superscriptCommand = UICommand(
            title: "Superscript",
            image: UIImage(systemName: "textformat.superscript"),
            action: #selector(toggleSuperscript(_:))
        )
        let subscriptCommand = UICommand(
            title: "Subscript",
            image: UIImage(systemName: "textformat.subscript"),
            action: #selector(toggleSubscript(_:))
        )
        let scriptMenu = UIMenu(
            title: "",
            identifier: UIMenu.Identifier("com.editabletext.script"),
            options: .displayInline,
            children: [superscriptCommand, subscriptCommand]
        )
        // macCatalyst: inserts into Format > Font in the menu bar
        // iOS: adds to the callout bubble
        builder.insertChild(scriptMenu, atStartOfMenu: .textStyle)

        super.buildMenu(with: builder)
    }

    // MARK: - Responder actions via AccessoryActions

    private var actions: AccessoryActions? {
        guard let binding = toolbar else { return nil }
        return AccessoryActions(toolbar: binding, inputClick: InputClickPlayer())
    }

    @objc func toggleSuperscript(_ sender: Any?) {
        actions?.toggleSuperscript()
    }

    @objc func toggleSubscript(_ sender: Any?) {
        actions?.toggleSubscript()
    }

    // Override BIU to go through AccessoryActions so justChanged / state sync stays correct
    @objc open override func toggleBoldface(_ sender: Any?) {
        if actions != nil { actions?.toggleBoldface() }
        else { super.toggleBoldface(sender) }
    }

    @objc open override func toggleItalics(_ sender: Any?) {
        if actions != nil { actions?.toggleItalics() }
        else { super.toggleItalics(sender) }
    }

    @objc open override func toggleUnderline(_ sender: Any?) {
        if actions != nil { actions?.toggleUnderline() }
        else { super.toggleUnderline(sender) }
    }
}

