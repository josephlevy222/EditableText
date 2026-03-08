//
//  FormattingPalette.swift
//
//  A floating formatting palette window for macCatalyst, analogous to the
//  system Fonts and Colors panels. Implemented as a second UIWindow on the
//  current UIWindowScene so it floats freely, is draggable, and never
//  interferes with the text view's layout.
//
//  Usage: EditableText calls FormattingPalette.shared.show(toolbar:) when
//  it gains focus and FormattingPalette.shared.detach() when it loses focus.
//
//  Requires iOS 15+. Uses ObservableObject (not @Observable) for compatibility.
//

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

// MARK: - Singleton palette manager

final class FormattingPalette {
    static let shared = FormattingPalette()
    private init() {}

    private var paletteWindow: UIWindow?
    private var hostingController: UIHostingController<AnyView>?

    // The observable box lets us swap which toolbar the palette is
    // pointing at without tearing down the window.
    private let box = ToolbarBox()

    /// Call when an EditableText gains focus.
    func show(toolbar: Binding<KeyboardToolbar>) {
        box.binding = toolbar
        if paletteWindow == nil { buildWindow() }
        paletteWindow?.isHidden = false
    }

    /// Call when an EditableText loses focus.
    func detach() {
        paletteWindow?.isHidden = true
    }

    private func buildWindow() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert         // floats above the main window
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = true

        let content = PaletteView(box: box)
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 100, y: 100, width: 460, height: 52)

        window.addSubview(host.view)
        window.frame = host.view.frame

        // Make the window draggable
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        window.addGestureRecognizer(pan)

        self.hostingController = host
        self.paletteWindow = window
        window.makeKeyAndVisible()
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let window = paletteWindow else { return }
        let delta = gr.translation(in: nil)
        gr.setTranslation(.zero, in: nil)
        window.frame = window.frame.offsetBy(dx: delta.x, dy: delta.y)
    }
}

// MARK: - Observable box that holds the active toolbar binding

/// ObservableObject (iOS 15 compatible) so PaletteView re-renders when a
/// new EditableText is focused and swaps in its toolbar binding.
final class ToolbarBox: ObservableObject {
    @Published var binding: Binding<KeyboardToolbar>? = nil
}

// MARK: - The palette SwiftUI view

private struct PaletteView: View {
    @ObservedObject var box: ToolbarBox

    var body: some View {
        if let binding = box.binding {
            FormattingPaletteContent(toolbar: binding)
        }
    }
}

// MARK: - Palette content (buttons, pickers)

struct FormattingPaletteContent: View {
    @Binding var toolbar: KeyboardToolbar
    private var accessory: KeyboardAccessoryView { KeyboardAccessoryView(toolbar: $toolbar) }
    private let buttonSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 3) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .padding(.leading, 6)

            Divider().frame(height: 20).padding(.horizontal, 2)

            // Bold / Italic / Underline / Strikethrough
            toolbarButton("bold",          highlighted: toolbar.isBold)          { accessory.toggleBoldface() }
            toolbarButton("italic",        highlighted: toolbar.isItalic)        { accessory.toggleItalics() }
            toolbarButton("underline",     highlighted: toolbar.isUnderline)     { accessory.toggleUnderline() }
            toolbarButton("strikethrough", highlighted: toolbar.isStrikethrough) { accessory.toggleStrikethrough() }

            Divider().frame(height: 20).padding(.horizontal, 2)

            // Super / Subscript
            toolbarButton("textformat.superscript", highlighted: toolbar.isSuperscript) { accessory.toggleSuperscript() }
            toolbarButton("textformat.subscript",   highlighted: toolbar.isSubscript)   { accessory.toggleSubscript() }

            Divider().frame(height: 20).padding(.horizontal, 2)

            // Font size
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

            // Text alignment
            Button { accessory.alignText() } label: {
                Image(systemName: toolbar.textAlignment.imageName)
            }
            .buttonStyle(.plain)
            .frame(width: buttonSize, height: buttonSize)

            Divider().frame(height: 20).padding(.horizontal, 2)

            // Color pickers — onChange single-argument form for iOS 15 compatibility
            ColorPicker("", selection: $toolbar.color, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .onChange(of: toolbar.color) { _ in accessory.selectColor() }

            ColorPicker("", selection: $toolbar.background, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .onChange(of: toolbar.background) { _ in accessory.selectBackground() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
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
