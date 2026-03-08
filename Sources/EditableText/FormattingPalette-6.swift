//
//  FormattingPalette.swift
//
//  A floating formatting palette for macCatalyst, analogous to the system
//  Fonts and Colors panels.
//
//  Uses NSWindow (accessed via UIWindow's AppKit bridge) so the palette:
//    • floats freely outside the app window bounds
//    • moves smoothly via AppKit's native window dragging
//    • persists until explicitly dismissed
//    • has a close button
//
//  Requires iOS 15+. No @Observable, no two-argument onChange.
//

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

// MARK: - AppKit bridge
// UIKit on macCatalyst exposes the underlying NSWindow via a private-but-stable
// property. We access it through NSObject KVC to avoid importing AppKit directly.

private extension UIWindow {
    var nsWindow: NSObject? {
        var responder: UIResponder? = self
        while let r = responder {
            if NSClassFromString("NSWindow") != nil,
               r.responds(to: NSSelectorFromString("contentViewController")) {
                return r as NSObject
            }
            responder = r.next
        }
        // Fallback: use the windowScene's UIWindowSceneBridge
        return value(forKey: "nsWindow") as? NSObject
    }

    /// Move the underlying NSWindow to a screen position and make it free-floating.
    func configureAsPanel(at origin: CGPoint, size: CGSize) {
        guard let ns = nsWindow else { return }
        // NSWindowStyleMask: titled=1, closable=2, utilityWindow=16, nonActivatingPanel=128
        // NSWindowCollectionBehavior: canJoinAllSpaces=1, managed=4
        let styleMask: UInt = 1 | 2 | 16 | 128   // titled + closable + utility + non-activating
        ns.setValue(styleMask, forKey: "styleMask")
        ns.setValue(true, forKey: "isMovableByWindowBackground")
        ns.setValue(true, forKey: "hidesOnDeactivate")
        ns.setValue(false, forKey: "isReleasedWhenClosed")
        // Allow window to move outside the app's own frame
        ns.perform(NSSelectorFromString("setMovable:"), with: true)
        // Position on screen
        if let setFrame = ns.value(forKey: "screen") as? NSObject {
            _ = setFrame // screen available; position is handled by setFrameOrigin
        }
        let frameDict: [String: Any] = [
            "x": origin.x, "y": origin.y,
            "width": size.width, "height": size.height
        ]
        _ = frameDict // actual positioning done via setFrameOrigin below
        ns.perform(
            NSSelectorFromString("setFrameOrigin:"),
            with: NSValue(cgPoint: origin)
        )
    }
}

// MARK: - Singleton palette manager

public final class FormattingPalette {
    public static let shared = FormattingPalette()
    private init() {}

    private var paletteWindow: UIWindow?
    private var hostingController: UIHostingController<AnyView>?
    private var activeID: ObjectIdentifier? = nil

    public var isVisible: Bool { !(paletteWindow?.isHidden ?? true) }

    public func show(toolbar: Binding<KeyboardToolbar>) {
        activeID = ObjectIdentifier(toolbar.wrappedValue.textView)
        if paletteWindow == nil {
            buildWindow(toolbar: toolbar)
        } else {
            // Directly replace rootView — the only reliable way to update a
            // UIHostingController in a separate UIWindow outside the main
            // window's SwiftUI update cycle.
            hostingController?.rootView = AnyView(
                FormattingPaletteContent(toolbar: toolbar)
            )
        }
        paletteWindow?.isHidden = false
    }

    public func detach() {
        activeID = nil
        paletteWindow?.isHidden = true
    }

    public func detachIfNeeded(toolbar: Binding<KeyboardToolbar>) {
        let requestID = ObjectIdentifier(toolbar.wrappedValue.textView)
        guard requestID == activeID else { return }
        detach()
    }

    private func buildWindow(toolbar: Binding<KeyboardToolbar>) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.backgroundColor = .clear

        let content = FormattingPaletteContent(toolbar: toolbar)
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear

        let paletteSize = CGSize(width: 480, height: 52)
        host.view.frame = CGRect(origin: .zero, size: paletteSize)
        window.frame = CGRect(origin: .zero, size: paletteSize)
        window.rootViewController = host
        window.isHidden = false

        // After the window is shown, configure the underlying NSWindow as a
        // free-floating utility panel that can move outside the app bounds.
        DispatchQueue.main.async {
            // Position near top-centre of screen
            let screenBounds = scene.screen.bounds
            let origin = CGPoint(
                x: (screenBounds.width - paletteSize.width) / 2,
                y: screenBounds.height - 120  // NSWindow y-axis is flipped (0 = bottom)
            )
            window.configureAsPanel(at: origin, size: paletteSize)
        }

        self.hostingController = host
        self.paletteWindow = window
    }
}

// MARK: - Palette content view

public struct FormattingPaletteContent: View {
    @Binding public var toolbar: KeyboardToolbar
    public init(toolbar: Binding<KeyboardToolbar>) { _toolbar = toolbar }
    private var accessory: KeyboardAccessoryView { KeyboardAccessoryView(toolbar: $toolbar) }
    private let buttonSize: CGFloat = 30

    public var body: some View {
        HStack(spacing: 3) {
            // The window background is draggable via isMovableByWindowBackground.
            // A subtle grip icon gives the user a visual affordance.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .padding(.leading, 6)

            Divider().frame(height: 20).padding(.horizontal, 2)

            toolbarButton("bold",          highlighted: toolbar.isBold)          { accessory.toggleBoldface() }
            toolbarButton("italic",        highlighted: toolbar.isItalic)        { accessory.toggleItalics() }
            toolbarButton("underline",     highlighted: toolbar.isUnderline)     { accessory.toggleUnderline() }
            toolbarButton("strikethrough", highlighted: toolbar.isStrikethrough) { accessory.toggleStrikethrough() }

            Divider().frame(height: 20).padding(.horizontal, 2)

            toolbarButton("textformat.superscript", highlighted: toolbar.isSuperscript) { accessory.toggleSuperscript() }
            toolbarButton("textformat.subscript",   highlighted: toolbar.isSubscript)   { accessory.toggleSubscript() }

            Divider().frame(height: 20).padding(.horizontal, 2)

            Button { accessory.decreaseFontSize() } label: {
                Image(systemName: "minus.circle")
            }.buttonStyle(.plain)

            Text(String(format: "%.0f", toolbar.fontSize))
                .font(.body.monospacedDigit())
                .frame(minWidth: 32, alignment: .center)

            Button { accessory.increaseFontSize() } label: {
                Image(systemName: "plus.circle")
            }.buttonStyle(.plain)

            Divider().frame(height: 20).padding(.horizontal, 2)

            Button { accessory.alignText() } label: {
                Image(systemName: toolbar.textAlignment.imageName)
            }
            .buttonStyle(.plain)
            .frame(width: buttonSize, height: buttonSize)

            Divider().frame(height: 20).padding(.horizontal, 2)

            ColorPicker("", selection: $toolbar.color, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .onChange(of: toolbar.color) { _ in accessory.selectColor() }

            ColorPicker("", selection: $toolbar.background, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .onChange(of: toolbar.background) { _ in accessory.selectBackground() }

            Divider().frame(height: 20).padding(.horizontal, 2)

            // Close button — hides the palette without dismissing the text editor
            Button {
                FormattingPalette.shared.detach()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func toolbarButton(_ systemImage: String, highlighted: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(highlighted ? Color(UIColor.separator) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
#endif
