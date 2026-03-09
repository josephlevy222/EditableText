//
//  FormattingPalette.swift
//
//  A floating formatting palette for macCatalyst.
//
//  Implementation: adds a UIHostingController as a child of the key window's
//  root view controller. This avoids all UIWindow hit-test and visibility
//  issues — the palette view is a normal subview of the main window, just
//  positioned absolutely and above everything else via zIndex / bringToFront.
//
//  Dragging: UIPanGestureRecognizer on the host view (not a SwiftUI gesture)
//  so UIKit handles hit testing and the gesture fires reliably.
//
//  Requires iOS 15+. No @Observable, no two-argument onChange.
//

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

// MARK: - Singleton palette manager

public final class FormattingPalette: NSObject, UIGestureRecognizerDelegate {
    public static let shared = FormattingPalette()
    private override init() {}

    private var hostingController: UIHostingController<AnyView>?
    private var activeID: ObjectIdentifier? = nil
    private var panGesture: UIPanGestureRecognizer?
    private var dragStartCenter: CGPoint = .zero

    public var isVisible: Bool {
        guard let hc = hostingController else { return false }
        return !hc.view.isHidden
    }

    /// Returns true if the given point (in the window's coordinate space)
    /// falls within the palette view. Use this instead of isVisible for
    /// tap filtering — isVisible is true even when the tap is beside the palette.
    public func contains(windowPoint point: CGPoint) -> Bool {
        guard let view = hostingController?.view, !view.isHidden else { return false }
        return view.frame.contains(point)
    }

    public func show(toolbar: Binding<KeyboardToolbar>) {
        activeID = ObjectIdentifier(toolbar.wrappedValue.textView)

        if hostingController == nil {
            build(toolbar: toolbar)
        } else {
            hostingController?.rootView = AnyView(
                FormattingPaletteContent(toolbar: toolbar)
            )
        }
        // Always bring to front and unhide — may have been covered by a
        // popover or sheet, or hidden by a previous detach()
        hostingController?.view.isHidden = false
        if let v = hostingController?.view {
            v.superview?.bringSubviewToFront(v)
        }
    }

    /// Hide the palette. Does NOT resign first responder — the user may
    /// still be editing. Tapping outside the text view ends editing normally.
    public func detach() {
        activeID = nil
        hostingController?.view.isHidden = true
    }

    /// Same as detach() — alias used by focus-loss and popover-disappear paths.
    public func detachHide() {
        detach()
    }

    public func detachIfNeeded(toolbar: Binding<KeyboardToolbar>) {
        guard ObjectIdentifier(toolbar.wrappedValue.textView) == activeID else { return }
        detachHide()
    }

    private func build(toolbar: Binding<KeyboardToolbar>) {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
        else { return }

        // Find the topmost window that has a rootViewController — prefer
        // non-alert windows. On macCatalyst isKeyWindow is unreliable
        // when popovers or sheets are open.
        let targetWindow = scene.windows
            .filter { !$0.isHidden && $0.rootViewController != nil }
            .max(by: { $0.windowLevel.rawValue < $1.windowLevel.rawValue })

        guard let rootVC = targetWindow?.rootViewController else { return }

        let paletteSize = CGSize(width: 500, height: 52)
        let windowWidth = rootVC.view.bounds.width
        let initialFrame = CGRect(
            x: (windowWidth - paletteSize.width) / 2,
            y: 80,  // below title bar in UIKit coords
            width: paletteSize.width,
            height: paletteSize.height
        )

        let content = FormattingPaletteContent(toolbar: toolbar)
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear
        host.view.frame = initialFrame

        // Add as child VC so it participates in the responder chain correctly
        rootVC.addChild(host)
        rootVC.view.addSubview(host.view)
        host.didMove(toParent: rootVC)
        rootVC.view.bringSubviewToFront(host.view)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        host.view.addGestureRecognizer(pan)
        self.panGesture = pan

        self.hostingController = host
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let view = gr.view else { return }
        switch gr.state {
        case .began:
            dragStartCenter = view.center
        case .changed:
            let t = gr.translation(in: view.superview)
            view.center = CGPoint(
                x: dragStartCenter.x + t.x,
                y: dragStartCenter.y + t.y
            )
        default:
            break
        }
    }

    // Only begin the pan when the touch starts in the leading ~60pt drag handle area.
    // This lets button taps in the rest of the palette fire without competing.
    public func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
        guard let view = gr.view else { return false }
        let location = gr.location(in: view)
        return location.x < 60
    }

    // Allow pan to coexist with SwiftUI internal gesture recognizers
    public func gestureRecognizer(_ gr: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return false
    }
}

// MARK: - Palette content view

public struct FormattingPaletteContent: View {
    @Binding public var toolbar: KeyboardToolbar

    public init(toolbar: Binding<KeyboardToolbar>) {
        _toolbar = toolbar
    }

    private var accessory: KeyboardAccessoryView { KeyboardAccessoryView(toolbar: $toolbar) }
    private let buttonSize: CGFloat = 30

    public var body: some View {
        HStack(spacing: 3) {

            // Drag handle — visual affordance; the pan gesture on the whole
            // view handles actual dragging so this is decoration only
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
                .padding(.trailing, 4)

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
        // Prevent the pan gesture on the host view from cancelling
        // SwiftUI button taps — buttons get priority
        .allowsHitTesting(true)
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
