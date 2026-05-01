//
//  KeyboardAccessoryView.swift
//
//  iPad:    full single-line toolbar (all controls)
//  iPhone:  compact two-line toolbar (essentials only)
//  Mac:     no inputAccessoryView — formatting via menu bar
//

import SwiftUI
import AVFoundation

// MARK: - KeyboardToolbar state

public struct KeyboardToolbar {
	var textView: RichTextView
	var isBold: Bool = false
	var isItalic: Bool = false
	var isUnderline: Bool = false
	var isStrikethrough: Bool = false
	var isSuperscript: Bool = false
	var isSubscript: Bool = false
	var fontSize: CGFloat = 17
	var textAlignment: NSTextAlignment = .center
	var color: Color = Color(uiColor: .label)
	var background: Color
	var sound: Bool = true
	var justChanged: Bool = false
	
	init(textView: RichTextView) {
		self.textView = textView
		self.background = Color(uiColor: UIColor.systemBackground.resolvedColor(with: textView.traitCollection))
	}
}

// MARK: - NSTextAlignment helpers

extension NSTextAlignment {
    var imageName: String {
        switch self {
        case .left:       "text.alignleft"
        case .center:     "text.aligncenter"
        case .right:      "text.alignright"
        case .justified:  "text.natural"
        case .natural:    "text.alignleft"
        @unknown default: "text.aligncenter"
        }
    }
    var textAlignment: TextAlignment {
        switch self {
        case .left:       .leading
        case .center:     .center
        case .right:      .trailing
        case .justified:  .leading
        case .natural:    .center
        @unknown default: .center
        }
    }
    static let available: [NSTextAlignment] = [.left, .right, .center]
}

// MARK: - Color Picker Popover

struct ColorPickerButton: View {
	@Binding var color: Color
	let systemImage: String
	let textView: RichTextView
	let isBackground: Bool
	
	// Track the currently presented picker and which button owns it
	private static var activePicker: UIColorPickerViewController?
	private static var activeIsBackground: Bool?
	private static var coordinatorKey: UInt8 = 0
	
	var body: some View {
		Button {
			let currentlyShowing = ColorPickerButton.activePicker != nil
			let sameButton = ColorPickerButton.activeIsBackground == isBackground
			
			// Always dismiss any active picker first
			if currentlyShowing {
				ColorPickerButton.activePicker?.dismiss(animated: false)
				ColorPickerButton.activePicker = nil
				ColorPickerButton.activeIsBackground = nil
				// If same button tapped, just dismiss and stop
				if sameButton { return }
			}
			
			// Present new picker
			let picker = UIColorPickerViewController()
			picker.selectedColor = UIColor(color)
			picker.supportsAlpha = true
			picker.modalPresentationStyle = .popover
			picker.popoverPresentationController?.sourceView = textView
			picker.popoverPresentationController?.sourceRect = CGRect(
				x: textView.bounds.midX, y: 0,
				width: 0, height: 0
			)
			picker.popoverPresentationController?.permittedArrowDirections = [.down,.up]
			
			let coordinator = ColorPickerCoordinator(
				color: $color, textView: textView, isBackground: isBackground,
				onDismiss: {
					ColorPickerButton.activePicker = nil
					ColorPickerButton.activeIsBackground = nil
				}
			)
			picker.delegate = coordinator
			objc_setAssociatedObject(picker, &ColorPickerButton.coordinatorKey,
									 coordinator, .OBJC_ASSOCIATION_RETAIN)
			
			ColorPickerButton.activePicker = picker
			ColorPickerButton.activeIsBackground = isBackground
			
			textView.parentViewController?.present(picker, animated: true)
		} label: {
			Image(systemName: systemImage)
				.foregroundStyle(isBackground ? textView.toolbar?.wrappedValue.color ?? .primary : color)
				.frame(width: 32, height: 32)//.border(.foreground)
				.background(
					isBackground ?
					RoundedRectangle(cornerRadius: 4).fill(color)
					: RoundedRectangle(cornerRadius: 4).fill(Color.clear)
				)
		}
		.buttonStyle(.plain)
	}
}

class ColorPickerCoordinator: NSObject, UIColorPickerViewControllerDelegate {
	@Binding var color: Color
	let textView: RichTextView
	let isBackground: Bool
	let onDismiss: () -> Void
	
	init(color: Binding<Color>, textView: RichTextView, isBackground: Bool,
		 onDismiss: @escaping () -> Void) {
		_color = color
		self.textView = textView
		self.isBackground = isBackground
		self.onDismiss = onDismiss
	}
	
	func colorPickerViewController(_ viewController: UIColorPickerViewController,
								   didSelect color: UIColor, continuously: Bool) {
		self.color = Color(uiColor: color)
		let range = textView.selectedRange
		let key: NSAttributedString.Key = isBackground ? .backgroundColor : .foregroundColor
		if !range.isEmpty {
			let str = NSMutableAttributedString(attributedString: textView.attributedText)
			str.addAttribute(key, value: color, range: range)
			textView.updateAttributedText(with: str)
			textView.selectedRange = range
		} else {
			textView.typingAttributes[key] = color
		}
	}
	
	func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
		onDismiss()
	}
}

// MARK: - AccessoryActions
// A struct holding a Binding<KeyboardToolbar> so all mutations propagate
// back through SwiftUI. Shared by both toolbar views and CustomizePopoverMenus.

public struct AccessoryActions {
    var toolbar: Binding<KeyboardToolbar>
    let inputClick: InputClickPlayer

    var textView: RichTextView { toolbar.wrappedValue.textView }
    var attributedText: NSAttributedString { textView.attributedText }
    var selectedRange: NSRange { textView.selectedRange }

    func updateAttributedText(with attributedString: NSAttributedString) {
        let selection = textView.selectedRange
        textView.updateAttributedText(with: attributedString)
        textView.selectedRange = selection
    }

	// Resolved system background for this text view — used when background attribute is absent so the ColorPicker shows the
	// correct opaque default rather than zero-opacity.
	var resolvedSystemBackground: Color {
		Color(uiColor: UIColor.systemBackground.resolvedColor(with: textView.traitCollection))
	}
	
    // MARK: Bold / Italic

    func toggleBoldface() { toggleSymbolicTrait(.traitBold) }
    func toggleItalics()  { toggleSymbolicTrait(.traitItalic) }

    func toggleSymbolicTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        inputClick.play(!toolbar.wrappedValue.sound)
        if selectedRange.isEmpty {
            toolbar.wrappedValue.justChanged = true
            let uiFont = textView.typingAttributes[.font] as? UIFont
            textView.typingAttributes[.font] = uiFont?.toggleSymbolicTrait(trait)
            textView.delegate?.textViewDidChangeSelection?(textView)
        } else {
            let attributedString = NSMutableAttributedString(attributedString: attributedText)
            var isAll = true
            attributedString.enumerateAttribute(.font, in: selectedRange, options: []) { value, _, stop in
                if let descriptor = (value as? UIFont)?.fontDescriptor {
                    let hasTrait = descriptor.symbolicTraits.intersection(trait) == trait
                    isAll = isAll && hasTrait
                    if !isAll { stop.pointee = true }
                }
            }
            attributedString.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                if isAll {
                    if let uiFont = (value as? UIFont)?.toggleSymbolicTrait(trait) {
                        attributedString.addAttribute(.font, value: uiFont, range: range)
                    }
                } else {
                    if let uiFont = value as? UIFont, !uiFont.contains(trait: trait) {
                        attributedString.addAttribute(.font,
                                                      value: uiFont.toggleSymbolicTrait(trait),
                                                      range: range)
                    }
                }
            }
            updateAttributedText(with: attributedString)
        }
    }

    // MARK: Underline

    func toggleUnderline() {
        inputClick.play(!toolbar.wrappedValue.sound)
        let attributedString = NSMutableAttributedString(attributedString: attributedText)
        if selectedRange.isEmpty {
            toolbar.wrappedValue.isUnderline.toggle()
            textView.typingAttributes[.underlineStyle] = toolbar.wrappedValue.isUnderline
                ? NSUnderlineStyle.single.rawValue : nil
            toolbar.wrappedValue.justChanged = true
            textView.delegate?.textViewDidChangeSelection?(textView)
            return
        }
        var isAll = true
        attributedString.enumerateAttribute(.underlineStyle, in: selectedRange, options: []) { value, _, stop in
            if value == nil { isAll = false; stop.pointee = true }
        }
        if isAll {
            attributedString.removeAttribute(.underlineStyle, range: selectedRange)
        } else {
            attributedString.addAttribute(.underlineStyle,
                                          value: NSUnderlineStyle.single.rawValue,
                                          range: selectedRange)
        }
        updateAttributedText(with: attributedString)
    }

    // MARK: Strikethrough

    func toggleStrikethrough() {
        inputClick.play(!toolbar.wrappedValue.sound)
        let attributedString = NSMutableAttributedString(attributedString: attributedText)
        if selectedRange.isEmpty {
            toolbar.wrappedValue.isStrikethrough.toggle()
            textView.typingAttributes[.strikethroughStyle] = toolbar.wrappedValue.isStrikethrough
                ? NSUnderlineStyle.single.rawValue : nil
            toolbar.wrappedValue.justChanged = true
            textView.delegate?.textViewDidChangeSelection?(textView)
            return
        }
        var isAll = true
        attributedString.enumerateAttribute(.strikethroughStyle, in: selectedRange, options: []) { value, _, stop in
            if value == nil { isAll = false; stop.pointee = true }
        }
        if isAll {
            attributedString.removeAttribute(.strikethroughStyle, range: selectedRange)
        } else {
            attributedString.addAttribute(.strikethroughStyle,
                                          value: NSUnderlineStyle.single.rawValue,
                                          range: selectedRange)
        }
        updateAttributedText(with: attributedString)
    }

    // MARK: Superscript / Subscript

    func toggleSuperscript() {
        toolbar.wrappedValue.isSuperscript.toggle()
        toggleScript(sub: false)
    }

    func toggleSubscript() {
        toolbar.wrappedValue.isSubscript.toggle()
        toggleScript(sub: true)
    }

    private func toggleScript(sub: Bool) {
        inputClick.play(!toolbar.wrappedValue.sound)
        let selectedRange = textView.selectedRange
        let newOffset: CGFloat = sub ? -0.3 : 0.4
        let attributedString = NSMutableAttributedString(attributedString: attributedText)

        if selectedRange.isEmpty {
            var fontSize = toolbar.wrappedValue.fontSize
            if toolbar.wrappedValue.isSubscript && toolbar.wrappedValue.isSuperscript {
                if sub { toolbar.wrappedValue.isSuperscript = false }
                else   { toolbar.wrappedValue.isSubscript   = false }
                textView.typingAttributes[.baselineOffset] = newOffset * toolbar.wrappedValue.fontSize
            }
            if !toolbar.wrappedValue.isSubscript && !toolbar.wrappedValue.isSuperscript {
                textView.typingAttributes[.baselineOffset] = nil
            } else {
                textView.typingAttributes[.baselineOffset] = newOffset * toolbar.wrappedValue.fontSize
                fontSize *= 0.75
            }
            if let font = textView.typingAttributes[.font] as? UIFont {
                var newFont = UIFont(descriptor: font.fontDescriptor, size: fontSize)
                if font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                    newFont = newFont.italic() ?? newFont
                }
                textView.typingAttributes[.font] = newFont
            }
            toolbar.wrappedValue.justChanged = true
            textView.delegate?.textViewDidChangeSelection?(textView)
            return
        }

        // Range-based toggle
        var isAllScript = true
        attributedString.enumerateAttributes(in: selectedRange, options: []) { attributes, range, _ in
            let offset = attributes[.baselineOffset] as? CGFloat ?? 0.0
            if offset == 0.0 {
                isAllScript = false
            } else {
                if let font = attributes[.font] as? UIFont {
                    let restored = UIFont(descriptor: font.fontDescriptor,
                                         size: font.pointSize / 0.75)
                    attributedString.removeAttribute(.baselineOffset, range: range)
                    attributedString.addAttribute(.font, value: restored, range: range)
                }
            }
        }
        if !isAllScript {
            attributedString.enumerateAttributes(in: selectedRange, options: []) { attributes, range, _ in
                if let font = attributes[.font] as? UIFont {
                    let isBold = font.contains(trait: .traitBold)
                    var newFont = UIFont(descriptor: font.fontDescriptor,
                                        size: font.pointSize * 0.75)
                    if font.fontDescriptor.symbolicTraits.contains(.traitItalic),
                       let italic = newFont.italic() {
                        newFont = isBold ? (italic.bold() ?? italic) : italic
                    }
                    attributedString.addAttribute(.baselineOffset,
                                                  value: newOffset * font.pointSize,
                                                  range: range)
                    attributedString.addAttribute(.font, value: newFont, range: range)
                }
            }
        }
        updateAttributedText(with: attributedString)
    }

    // MARK: Alignment

    func alignText() {
        inputClick.play(!toolbar.wrappedValue.sound)
        toolbar.wrappedValue.textAlignment = switch toolbar.wrappedValue.textAlignment {
            case .left:       .center
            case .center:     .right
            case .right:      .left
            case .justified:  .justified
            case .natural:    .center
            @unknown default: .left
        }
        textView.textAlignment = toolbar.wrappedValue.textAlignment
        if let update = textView.delegate?.textViewDidChange { update(textView) }
    }

    // MARK: Font size

    func increaseFontSize() { adjustFontSize(isIncrease: true) }
    func decreaseFontSize() { adjustFontSize(isIncrease: false) }

    private func adjustFontSize(isIncrease: Bool) {
        inputClick.play(!toolbar.wrappedValue.sound)
        let textRange = textView.selectedRange
        let defaultFont = UIFont.preferredFont(forTextStyle: .body)
        let maxFontSize: CGFloat = 80
        let minFontSize: CGFloat = 8

        if textRange.isEmpty {
            let font = textView.typingAttributes[.font] as? UIFont ?? defaultFont
            let offset = textView.typingAttributes[.baselineOffset] as? CGFloat ?? 0.0
            let size = toolbar.wrappedValue.fontSize
            let newSize = CGFloat(Int(size + CGFloat(isIncrease
                ? (size < maxFontSize ? 1 : 0)
                : (size > minFontSize ? -1 : 0)) + 0.5))
            textView.typingAttributes[.font] = UIFont(descriptor: font.fontDescriptor,
                                                      size: newSize * (offset == 0 ? 1.0 : 0.75))
            toolbar.wrappedValue.fontSize = newSize
        } else {
            let attributedString = NSMutableAttributedString(attributedString: attributedText)
            textView.attributedText.enumerateAttributes(in: textRange) { attributes, range, _ in
                let font = attributes[.font] as? UIFont ?? defaultFont
                let offset = attributes[.baselineOffset] as? CGFloat ?? 0.0
                let size = font.pointSize / (offset == 0 ? 1.0 : 0.75)
                let newSize = CGFloat(Int(size + CGFloat(isIncrease
                    ? (size < maxFontSize ? 1 : 0)
                    : (size > minFontSize ? -1 : 0)) + 0.5))
                let newFont = UIFont(descriptor: font.fontDescriptor,
                                     size: newSize * (offset == 0 ? 1.0 : 0.75))
                attributedString.addAttribute(.font, value: newFont, range: range)
            }
            textView.updateAttributedText(with: attributedString)
            textView.selectedRange = textRange
        }
    }

    // MARK: Colors

    func selectColor() {
        let color = UIColor(toolbar.wrappedValue.color)
        textEffect(range: textView.selectedRange, key: .foregroundColor,
                   value: color, defaultValue: color)
    }

    func selectBackground() {
        let color = UIColor(toolbar.wrappedValue.background)
        textEffect(range: textView.selectedRange, key: .backgroundColor,
                   value: color, defaultValue: color)
    }

    private func textEffect<T: Equatable>(range: NSRange,
                                          key: NSAttributedString.Key,
                                          value: T, defaultValue: T) {
        inputClick.play(!toolbar.wrappedValue.sound)
        if !range.isEmpty {
            let mutableString = NSMutableAttributedString(attributedString: textView.attributedText)
            mutableString.removeAttribute(key, range: range)
            mutableString.addAttributes([key: value], range: range)
            textView.updateAttributedText(with: mutableString)
        } else {
            if let current = textView.typingAttributes[key], current as! T == value {
                textView.typingAttributes[key] = defaultValue
            } else {
                textView.typingAttributes[key] = value
            }
        }
        textView.selectedRange = range
    }
}

// MARK: - Shared toolbar button style

private struct ToolbarButtonStyle: ViewModifier {
    let highlighted: Bool
    let size: CGFloat
    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
			.foregroundStyle(Color(highlighted ? UIColor.tintColor : UIColor.label))
            .background(
                RoundedRectangle(cornerRadius: 6)
					.fill( Color(highlighted ? UIColor.separator : UIColor.quaternarySystemFill) )
				)
    }
}

// MARK: - iPad: Full single-line toolbar

public struct KeyboardAccessoryView: View {
    @Binding public var toolbar: KeyboardToolbar
    private let inputClick = InputClickPlayer()
    private var actions: AccessoryActions {
        AccessoryActions(toolbar: $toolbar, inputClick: inputClick)
    }

    private let buttonSize: CGFloat = 32
    private let toolBarsBackground = UIColor.systemGroupedBackground
	
    public var body: some View {
        HStack(spacing: 1) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    toolbarButton("bold",              highlighted: toolbar.isBold)          { actions.toggleBoldface() }
                    toolbarButton("italic",            highlighted: toolbar.isItalic)        { actions.toggleItalics() }
                    toolbarButton("underline",         highlighted: toolbar.isUnderline)     { actions.toggleUnderline() }
                    toolbarButton("strikethrough",     highlighted: toolbar.isStrikethrough) { actions.toggleStrikethrough() }

                    Divider().frame(height: 20).padding(.horizontal, 4)

                    toolbarButton("textformat.superscript",highlighted: toolbar.isSuperscript)  { actions.toggleSuperscript() }
                    toolbarButton("textformat.subscript",highlighted: toolbar.isSubscript)    { actions.toggleSubscript() }

                    Divider().frame(height: 20).padding(.horizontal, 4)

                    Button { actions.decreaseFontSize() } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain)
                    Text(String(format: "%.0f", toolbar.fontSize))
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 28, alignment: .center)
                    Button { actions.increaseFontSize() } label: {
                        Image(systemName: "plus.circle")
                    }.buttonStyle(.plain)

                    Divider().frame(height: 20).padding(.horizontal, 4)

                    Button { actions.alignText() } label: {
                        Image(systemName: toolbar.textAlignment.imageName)
                            .frame(width: buttonSize, height: buttonSize)
                    }.buttonStyle(.plain)

                    Divider().frame(height: 20).padding(.horizontal, 4)
					ColorPickerButton(color: $toolbar.color,
									  systemImage: "character",
									  textView: toolbar.textView,
									  isBackground: false)
					ColorPickerButton(color: $toolbar.background,
									  systemImage: "a.square",
									  textView: toolbar.textView,
									  isBackground: true)
                }
                .padding(.horizontal, 4)
            }
            Spacer()
            Button { toolbar.sound.toggle() } label: {
                Image(systemName: toolbar.sound ? "speaker" : "speaker.slash")
            }.buttonStyle(.plain).padding(.horizontal, 4)
            Button { toolbar.textView.resignFirstResponder() } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }.buttonStyle(.plain).padding(.horizontal, 8)
        }
        .frame(height: 44)
        .background(Color(toolBarsBackground))
    }

    private func toolbarButton(_ symbol: String, highlighted: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .modifier(ToolbarButtonStyle(highlighted: highlighted, size: buttonSize))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - iPhone: Compact two-line toolbar

public struct CompactKeyboardAccessoryView: View {
    @Binding public var toolbar: KeyboardToolbar
    private let inputClick = InputClickPlayer()
    private var actions: AccessoryActions {
        AccessoryActions(toolbar: $toolbar, inputClick: inputClick)
    }

    private let buttonSize: CGFloat = 30
    private let toolBarsBackground = UIColor.systemGroupedBackground

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            // Line 1: BIU + strikethrough + super/subscript + dismiss
            HStack(spacing: 2) {
                toolbarButton("bold",                   highlighted: toolbar.isBold)          { actions.toggleBoldface() }
                toolbarButton("italic",                 highlighted: toolbar.isItalic)        { actions.toggleItalics() }
                toolbarButton("underline",              highlighted: toolbar.isUnderline)     { actions.toggleUnderline() }
                toolbarButton("strikethrough",          highlighted: toolbar.isStrikethrough) { actions.toggleStrikethrough() }

                Divider().frame(height: 18).padding(.horizontal, 2)

                toolbarButton("textformat.superscript", highlighted: toolbar.isSuperscript)  { actions.toggleSuperscript() }
                toolbarButton("textformat.subscript",   highlighted: toolbar.isSubscript)    { actions.toggleSubscript() }

                Spacer()

                Button { toolbar.textView.resignFirstResponder() } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }.buttonStyle(.plain).padding(.horizontal, 8)
            }
            .padding(.horizontal, 4)
            .frame(height: 36)

            Divider()

            // Line 2: font size + alignment + colors + sound
            HStack(spacing: 2) {
                Button { actions.decreaseFontSize() } label: {
                    Image(systemName: "minus.circle")
                }.buttonStyle(.plain)
                Text(String(format: "%.0f", toolbar.fontSize))
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 24, alignment: .center)
                Button { actions.increaseFontSize() } label: {
                    Image(systemName: "plus.circle")
                }.buttonStyle(.plain)

                Divider().frame(height: 18).padding(.horizontal, 4)

                Button { actions.alignText() } label: {
                    Image(systemName: toolbar.textAlignment.imageName)
                        .frame(width: buttonSize, height: buttonSize)
                }.buttonStyle(.plain)

                Divider().frame(height: 18).padding(.horizontal, 4)

				ColorPickerButton(color: $toolbar.color,
								  systemImage: "character",
								  textView: toolbar.textView,
								  isBackground: false)
				ColorPickerButton(color: $toolbar.background,
								  systemImage: "a.square",
								  textView: toolbar.textView,
								  isBackground: true)
                Spacer()

                Button { toolbar.sound.toggle() } label: {
                    Image(systemName: toolbar.sound ? "speaker" : "speaker.slash")
                }.buttonStyle(.plain).padding(.horizontal, 8)
            }
            .padding(.horizontal, 4)
            .frame(height: 36)
        }
        .background(Color(toolBarsBackground))
    }

    private func toolbarButton(_ symbol: String, highlighted: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .modifier(ToolbarButtonStyle(highlighted: highlighted, size: buttonSize))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Coordinator: UITextViewDelegate + toolbar state sync

extension RichTextEditor.Coordinator: UITextViewDelegate {

//    public func textViewDidChange(_ textView: UITextView) {
//        parent.attributedText = textView.attributedText.attributedStringFromUIKit
//        parent.alignment = textView.textAlignment.textAlignment
//        updateToolbarState(for: textView)
//    }
//
//    public func textViewDidChangeSelection(_ textView: UITextView) {
//        DispatchQueue.main.async {
//            self.parent.alignment = textView.textAlignment.textAlignment
//            self.updateToolbarState(for: textView)
//        }
//    }
//
//    public func textViewDidEndEditing(_ textView: UITextView) {
//        parent.alignment = textView.textAlignment.textAlignment
//    }
//
//    public func textViewDidBeginEditing(_ textView: UITextView) {
//        textView.textAlignment = switch parent.alignment {
//            case .leading: .left; case .center: .center; case .trailing: .right
//        }
//    }

    func updateToolbarState(for textView: UITextView) {
        guard let tv = textView as? RichTextView,
              let toolbarBinding = tv.toolbar else { return }

        // Don't clobber state just set by a button tap
        guard !toolbarBinding.wrappedValue.justChanged else {
            toolbarBinding.wrappedValue.justChanged = false
            return
        }

        let range = textView.selectedRange
        let attrs: [NSAttributedString.Key: Any]
        if range.length > 0 && range.location < textView.textStorage.length {
            attrs = textView.textStorage.attributes(at: range.location, effectiveRange: nil)
        } else if range.location > 0 && range.location <= textView.textStorage.length {
            attrs = textView.textStorage.attributes(at: range.location - 1, effectiveRange: nil)
        } else {
            attrs = textView.typingAttributes
        }

        let font   = attrs[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
        let offset = attrs[.baselineOffset] as? CGFloat ?? 0

        toolbarBinding.wrappedValue.isBold          = font.fontDescriptor.symbolicTraits.contains(.traitBold)
        toolbarBinding.wrappedValue.isItalic        = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        toolbarBinding.wrappedValue.isUnderline     = (attrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
        toolbarBinding.wrappedValue.isStrikethrough = (attrs[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue
        toolbarBinding.wrappedValue.isSuperscript   = offset > 0
        toolbarBinding.wrappedValue.isSubscript     = offset < 0
        toolbarBinding.wrappedValue.color           = Color(uiColor: attrs[.foregroundColor] as? UIColor ?? .label)
		let rawBackground = attrs[.backgroundColor] as? UIColor ?? UIColor.systemBackground
		toolbarBinding.wrappedValue.background 		= Color(uiColor: rawBackground.resolvedColor(with: tv.traitCollection))
//      toolbarBinding.wrappedValue.background      = Color(uiColor: attrs[.backgroundColor] as? UIColor ?? .clear)
        toolbarBinding.wrappedValue.textAlignment   = textView.textAlignment
        toolbarBinding.wrappedValue.fontSize        = font.pointSize / (offset == 0 ? 1.0 : 0.75)
    }
}

// MARK: - InputClickPlayer

public class InputClickPlayer {
    private var soundID: SystemSoundID
    public init() {
        soundID = 0
        if let filePath = Bundle.main.path(forResource: "sound56", ofType: "wav") {
            AudioServicesCreateSystemSoundID(URL(fileURLWithPath: filePath) as CFURL, &soundID)
        }
    }
    public func play(_ mute: Bool) { if !mute { AudioServicesPlaySystemSound(soundID) } }
}

// MARK: - Image picker (Coordinator extension)

extension RichTextEditor.Coordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController,
                                      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let img = info[.editedImage] as? UIImage,
           let image = img.roundedImageWithBorder(color: .secondarySystemBackground) {
            let newString = NSMutableAttributedString(attributedString: parent.textView.attributedText)
            let scaled = scaleImage(image: image, maxWidth: 180, maxHeight: 180)
            newString.append(NSAttributedString(attachment: NSTextAttachment(image: scaled)))
            parent.textView.attributedText = newString
            textViewDidChange(parent.textView)
        }
        picker.dismiss(animated: true)
    }

    func insertImage() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = true
        picker.sourceType = .photoLibrary
        parent.textView.parentViewController?.present(picker, animated: true)
    }

    func scaleImage(image: UIImage, maxWidth: CGFloat, maxHeight: CGFloat) -> UIImage {
        let ratio = image.size.width / image.size.height
        let w: CGFloat = ratio >= 1 ? maxWidth  : image.size.width  * (maxHeight / image.size.height)
        let h: CGFloat = ratio <= 1 ? maxHeight : image.size.height * (maxWidth  / image.size.width)
        UIGraphicsBeginImageContext(CGSize(width: w, height: h))
        image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? image
    }
}
