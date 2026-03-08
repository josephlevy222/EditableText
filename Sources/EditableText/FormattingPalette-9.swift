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
//
// On macCatalyst every UIWindow is backed by an NSWindow. The path to it is:
//   UIWindow → windowScene → _nsWindowSceneBridge → nsWindow
//
// All three steps use KVC on NSObject so we never import AppKit directly.
// The bridge object is a UINSWindowMapper / _UIWindowSceneBridge (private class)
// that forwards KVC to the real NSWindow.
//
// IMPORTANT: call configureAsPanel() only after the window is visible
// (i.e. inside a DispatchQueue.main.async after isHidden = false),
// otherwise the bridge hasn't been created yet and nsWindow returns nil.

private extension UIWindow {

    /// The underlying NSWindow, reached via the scene bridge.
    var nsWindow: NSObject? {
        // UIWindowScene → _nsWindowSceneBridge → nsWindow
        guard let scene = windowScene as? NSObject else { return nil }
        // "_nsWindowSceneBridge" is stable across macCatalyst 13–17+
        guard scene.responds(to: NSSelectorFromString("_nsWindowSceneBridge")),
              let bridge = scene.value(forKey: "_nsWindowSceneBridge") as? NSObject
        else { return nil }
        return bridge.value(forKey: "nsWindow") as? NSObject
    }

    /// Configure the underlying NSWindow as a free-floating utility panel.
    /// Must be called after the window is visible so the bridge exists.
    func configureAsPanel(at origin: CGPoint, size: CGSize) {
        guard let ns = nsWindow else {
            print("[FormattingPalette] nsWindow nil — retrying in 0.1s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.configureAsPanel(at: origin, size: size)
            }
            return
        }
        print("[FormattingPalette] nsWindow found: \(ns)")

        // NSWindowStyleMask bits (AppKit constants without importing AppKit):
        //   titled            = 1
        //   closable          = 2
        //   utilityWindow     = 16   → makes it an NSPanel subclass visually
        //   nonActivatingPanel = 128 → clicking palette doesn't steal key window
        let styleMask: UInt = 1 | 2 | 16 | 128
        ns.setValue(styleMask, forKey: "styleMask")

        // NSFloatingWindowLevel = 3: sits above all normal windows including the
        // app's own main window. This is what keeps the palette on top of the app.
        // (UIWindow.Level.alert only affects UIKit z-order, not NSWindow level.)
        ns.setValue(Int(3), forKey: "level")

        // isMovableByWindowBackground: dragging anywhere on the window moves it,
        // matching the behaviour of the system Fonts / Colors panels.
        ns.setValue(true, forKey: "isMovableByWindowBackground")

        // Keep visible when the app is not front-most (like the system panels)
        ns.setValue(false, forKey: "hidesOnDeactivate")

        // Standard memory management — don't release on close
        ns.setValue(false, forKey: "isReleasedWhenClosed")

        // Current frame before move
        if let currentFrame = ns.value(forKey: "frame") as? CGRect {
            print("[FormattingPalette] current NSWindow frame=\(currentFrame)")
        }
        // Position: NSWindow origin is bottom-left (y=0 at bottom of screen).
        // setFrameOrigin: takes an NSPoint (= CGPoint on macOS).
        print("[FormattingPalette] calling setFrameOrigin: \(origin)")
        ns.perform(NSSelectorFromString("setFrameOrigin:"),
                   with: NSValue(cgPoint: origin))
        // Verify the move took effect
        if let newFrame = ns.value(forKey: "frame") as? CGRect {
            print("[FormattingPalette] NSWindow frame after setFrameOrigin=\(newFrame)")
        }
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

        // After the window is visible, configure the underlying NSWindow as a
        // free-floating utility panel. Must be deferred so the scene bridge exists.
        DispatchQueue.main.async {
            // Get the NSWindow to read the NSScreen frame for coordinate conversion.
            // NSScreen.frame is in AppKit screen coordinates (y=0 at bottom of
            // the primary screen). The menu bar is at the top, so usable content
            // starts at screenFrame.height - menuBarHeight from the bottom.
            // We place the palette just below a typical toolbar (~100 pts from top).
            guard let ns = window.nsWindow,
                  let nsScreen = ns.value(forKey: "screen") as? NSObject,
                  let screenFrame = nsScreen.value(forKey: "frame") as? CGRect
            else {
                print("[FormattingPalette] screen KVC failed — using UIKit fallback")
                print("[FormattingPalette] nsWindow=\(String(describing: window.nsWindow))")
                let screenBounds = scene.screen.bounds
                print("[FormattingPalette] UIKit screenBounds=\(screenBounds)")
                let origin = CGPoint(
                    x: (screenBounds.width - paletteSize.width) / 2,
                    y: screenBounds.height - 150
                )
                window.configureAsPanel(at: origin, size: paletteSize)
                return
            }
            print("[FormattingPalette] NSScreen frame=\(screenFrame)")
            let origin = CGPoint(
                x: screenFrame.minX + (screenFrame.width - paletteSize.width) / 2,
                y: screenFrame.maxY - 100 - paletteSize.height
            )
            print("[FormattingPalette] placing at origin=\(origin)")
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
