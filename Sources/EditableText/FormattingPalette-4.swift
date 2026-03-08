//
//  FormattingPalette.swift
//
//  A floating formatting palette window for macCatalyst, analogous to the
//  system Fonts and Colors panels. Implemented as a second UIWindow on the
//  current UIWindowScene so it floats freely, is draggable, and never
//  interferes with the text view's layout.
//
//  Requires iOS 15+. Uses ObservableObject (not @Observable) for compatibility.
//

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

// MARK: - Passthrough window
// Only receives touches that land on actual opaque/interactive content.
// Transparent areas return nil from hitTest so touches fall through to
// whatever is underneath — prevents the palette from stealing taps from
// the plot or other views.

private class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        // If the hit view is the window itself or the hosting controller's
        // root view background, let the touch fall through.
        return hitView == self || hitView == rootViewController?.view ? nil : hitView
    }
}

// MARK: - Singleton palette manager

public final class FormattingPalette {
    public static let shared = FormattingPalette()
    private init() {}

    private var paletteWindow: PassthroughWindow?
    private var hostView: UIView?
    private let box = ToolbarBox()

    /// Call when an EditableText gains focus.
    public func show(toolbar: Binding<KeyboardToolbar>) {
        activeID = ObjectIdentifier(toolbar.wrappedValue.textView)
        box.binding = toolbar
        if paletteWindow == nil { buildWindow() }
        paletteWindow?.isHidden = false
    }

    private var activeID: ObjectIdentifier? = nil

    /// True when the palette window is showing. Used by XYPlot to suppress
    /// PlotSettings presentation when a toolbar button tap passes through.
    public var isVisible: Bool { !(paletteWindow?.isHidden ?? true) }

    /// Call when an EditableText loses focus (unconditional hide).
    public func detach() {
        activeID = nil
        paletteWindow?.isHidden = true
    }

    /// Only hides if no other EditableText has grabbed focus since detach was
    /// scheduled. Compares by the ObjectIdentifier of the RichTextView so a
    /// rapid X->Y focus transfer doesn't flash the palette away.
    public func detachIfNeeded(toolbar: Binding<KeyboardToolbar>) {
        let requestID = ObjectIdentifier(toolbar.wrappedValue.textView)
        guard requestID == activeID else { return }
        detach()
    }

    private func buildWindow() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }

        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = true

        let content = PaletteView(box: box)
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear

        let paletteSize = CGSize(width: 480, height: 52)
        host.view.frame = CGRect(origin: .zero, size: paletteSize)

        // Position palette near the top of the screen, centred
        let screenBounds = scene.screen.bounds
        let origin = CGPoint(
            x: (screenBounds.width - paletteSize.width) / 2,
            y: 80
        )
        window.frame = CGRect(origin: origin, size: paletteSize)
        window.addSubview(host.view)

        self.hostView = host.view
        self.paletteWindow = window

        // Use isHidden rather than makeKeyAndVisible so we don't steal
        // key window status from the main window (which would break focus).
        window.isHidden = false
    }

    /// Called from the SwiftUI DragGesture on the palette's drag handle.
    /// `translation` is cumulative from drag start, so we track the origin.
    private var dragStartOrigin: CGPoint = .zero
    var isDragging = false

    func dragStarted() {
        isDragging = true
        dragStartOrigin = paletteWindow?.frame.origin ?? .zero
    }

    func dragMoved(translation: CGSize) {
        guard let window = paletteWindow else { return }
        window.frame.origin = CGPoint(
            x: dragStartOrigin.x + translation.width,
            y: dragStartOrigin.y + translation.height
        )
    }
}

// MARK: - Observable box

final class ToolbarBox: ObservableObject {
    @Published var binding: Binding<KeyboardToolbar>? = nil
}

// MARK: - Palette SwiftUI views

private struct PaletteView: View {
    @ObservedObject var box: ToolbarBox
    var body: some View {
        if let binding = box.binding {
            FormattingPaletteContent(toolbar: binding)
        }
    }
}

public struct FormattingPaletteContent: View {
    @Binding public var toolbar: KeyboardToolbar
    public init(toolbar: Binding<KeyboardToolbar>) { _toolbar = toolbar }
    private var accessory: KeyboardAccessoryView { KeyboardAccessoryView(toolbar: $toolbar) }
    private let buttonSize: CGFloat = 30

    public var body: some View {
        HStack(spacing: 3) {
            // Drag handle — drag this to move the palette window
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .padding(.leading, 6)
                .padding(.trailing, 4)
                .contentShape(Rectangle().size(CGSize(width: 44, height: 44)))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // startLocation is constant for the lifetime of one drag,
                            // so first call sets origin, subsequent calls move the window.
                            if !FormattingPalette.shared.isDragging {
                                FormattingPalette.shared.dragStarted()
                            }
                            FormattingPalette.shared.dragMoved(translation: value.translation)
                        }
                        .onEnded { _ in
                            FormattingPalette.shared.isDragging = false
                        }
                )

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
