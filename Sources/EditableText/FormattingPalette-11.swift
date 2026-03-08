//
//  FormattingPalette.swift
//
//  A floating formatting palette for macCatalyst.
//
//  Implementation notes:
//  • Uses a UIWindow at .alert+1 level so it floats above all app content.
//  • The NSWindow bridge is NOT available on auxiliary UIWindows on macCatalyst —
//    only the app's root window gets bridged. So we stay in UIKit entirely.
//  • Dragging is handled by a SwiftUI DragGesture on the drag handle that calls
//    back to update the UIWindow frame directly — smooth because we bypass the
//    SwiftUI layout engine for the frame mutation.
//  • The window is confined to the screen bounds of the app window, which is
//    normal behaviour for macCatalyst apps that haven't adopted multi-window.
//
//  Requires iOS 15+. No @Observable, no two-argument onChange.
//

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

// MARK: - Passthrough window
// Transparent areas return nil from hitTest so touches fall through to
// whatever is underneath — prevents stealing taps from the plot or text views.

private class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        return hitView == self || hitView == rootViewController?.view ? nil : hitView
    }
}

// MARK: - Singleton palette manager

public final class FormattingPalette {
    public static let shared = FormattingPalette()
    private init() {}

    private var paletteWindow: PassthroughWindow?
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
            // SwiftUI update cycle.
            hostingController?.rootView = AnyView(
                FormattingPaletteContent(toolbar: toolbar, onDrag: { [weak self] in
                    self?.paletteWindow?.frame
                }, setFrame: { [weak self] frame in
                    self?.paletteWindow?.frame = frame
                })
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

        let paletteSize = CGSize(width: 500, height: 52)

        // Position near top-centre of the app window
        let screenBounds = scene.screen.bounds
        let initialOrigin = CGPoint(
            x: (screenBounds.width - paletteSize.width) / 2,
            y: 80  // below menu bar + title bar in UIKit coords (y=0 at top)
        )
        let initialFrame = CGRect(origin: initialOrigin, size: paletteSize)

        let window = PassthroughWindow(windowScene: scene)
        // Use a very high window level so we're above everything in the app
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 100)
        window.backgroundColor = .clear
        window.frame = initialFrame

        let content = FormattingPaletteContent(
            toolbar: toolbar,
            onDrag: { window.frame },
            setFrame: { window.frame = $0 }
        )
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: paletteSize)
        window.rootViewController = host
        window.isHidden = false

        self.hostingController = host
        self.paletteWindow = window
    }
}

// MARK: - Palette content view

public struct FormattingPaletteContent: View {
    @Binding public var toolbar: KeyboardToolbar
    // Callbacks into FormattingPalette to read/write UIWindow.frame directly.
    // Using closures rather than a shared reference keeps the view value-typed.
    let onDrag: () -> CGRect?
    let setFrame: (CGRect) -> Void

    public init(toolbar: Binding<KeyboardToolbar>,
                onDrag: @escaping () -> CGRect?,
                setFrame: @escaping (CGRect) -> Void) {
        _toolbar = toolbar
        self.onDrag = onDrag
        self.setFrame = setFrame
    }

    private var accessory: KeyboardAccessoryView { KeyboardAccessoryView(toolbar: $toolbar) }
    private let buttonSize: CGFloat = 30

    // Track the window origin at drag start so we can apply cumulative translation
    @State private var dragStartOrigin: CGPoint = .zero
    @State private var isDragging = false

    public var body: some View {
        HStack(spacing: 3) {

            // ── Drag handle ───────────────────────────────────────────────
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .frame(width: 28, height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartOrigin = onDrag()?.origin ?? .zero
                            }
                            let newOrigin = CGPoint(
                                x: dragStartOrigin.x + value.translation.width,
                                y: dragStartOrigin.y + value.translation.height
                            )
                            if let current = onDrag() {
                                setFrame(CGRect(origin: newOrigin, size: current.size))
                            }
                        }
                        .onEnded { _ in isDragging = false }
                )

            Divider().frame(height: 20).padding(.horizontal, 2)

            // ── Text style ────────────────────────────────────────────────
            toolbarButton("bold",          highlighted: toolbar.isBold)          { accessory.toggleBoldface() }
            toolbarButton("italic",        highlighted: toolbar.isItalic)        { accessory.toggleItalics() }
            toolbarButton("underline",     highlighted: toolbar.isUnderline)     { accessory.toggleUnderline() }
            toolbarButton("strikethrough", highlighted: toolbar.isStrikethrough) { accessory.toggleStrikethrough() }

            Divider().frame(height: 20).padding(.horizontal, 2)

            // ── Super / subscript ─────────────────────────────────────────
            toolbarButton("textformat.superscript", highlighted: toolbar.isSuperscript) { accessory.toggleSuperscript() }
            toolbarButton("textformat.subscript",   highlighted: toolbar.isSubscript)   { accessory.toggleSubscript() }

            Divider().frame(height: 20).padding(.horizontal, 2)

            // ── Font size ─────────────────────────────────────────────────
            Button { accessory.decreaseFontSize() } label: {
                Image(systemName: "minus.circle")
            }.buttonStyle(.plain)

            Text(String(format: "%.0f", toolbar.fontSize))
                .font(.body.monospacedDigit())
                .frame(minWidth: 28, alignment: .center)

            Button { accessory.increaseFontSize() } label: {
                Image(systemName: "plus.circle")
            }.buttonStyle(.plain)

            Divider().frame(height: 20).padding(.horizontal, 2)

            // ── Alignment ─────────────────────────────────────────────────
            Button { accessory.alignText() } label: {
                Image(systemName: toolbar.textAlignment.imageName)
            }
            .buttonStyle(.plain)
            .frame(width: buttonSize, height: buttonSize)

            Divider().frame(height: 20).padding(.horizontal, 2)

            // ── Colors ────────────────────────────────────────────────────
            ColorPicker("", selection: $toolbar.color, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .onChange(of: toolbar.color) { _ in accessory.selectColor() }

            ColorPicker("", selection: $toolbar.background, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .onChange(of: toolbar.background) { _ in accessory.selectBackground() }

            Divider().frame(height: 20).padding(.horizontal, 2)

            // ── Close ─────────────────────────────────────────────────────
            Button {
                FormattingPalette.shared.detach()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
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
