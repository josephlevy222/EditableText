//
//  ScrollAwareKit.swift
//
//
//  Created by Joseph Levy on 5/3/26.

//
//  Unified SwiftUI + UIKit field awareness with keyboard-aware scrolling
//

import SwiftUI
import Combine
import UIKit
import ObjectiveC.runtime

// MARK: - Environment keys

private struct FocusedIDBindingKey: EnvironmentKey {
	static let defaultValue: Binding<AnyHashable?>? = nil
}

private struct FocusedFrameBindingKey: EnvironmentKey {
	static let defaultValue: Binding<CGRect?>? = nil
}

extension EnvironmentValues {
	var focusedIDBinding: Binding<AnyHashable?>? {
		get { self[FocusedIDBindingKey.self] }
		set { self[FocusedIDBindingKey.self] = newValue }
	}
	
	var focusedFrameBinding: Binding<CGRect?>? {
		get { self[FocusedFrameBindingKey.self] }
		set { self[FocusedFrameBindingKey.self] = newValue }
	}
}

// MARK: - Preference key

struct FieldFramePreferenceKey: PreferenceKey {
	static var defaultValue: [AnyHashable: CGRect] = [:]
	
	static func reduce(value: inout [AnyHashable: CGRect],
					   nextValue: () -> [AnyHashable: CGRect]) {
		value.merge(nextValue(), uniquingKeysWith: { $1 })
	}
}

// MARK: - ScrollAware

struct ScrollAware: ViewModifier {
	var externalFocusedID: Binding<AnyHashable?>?
	var externalFocusedFrame: Binding<CGRect?>?
	
	@State private var internalFocusedID: AnyHashable?
	@State private var internalFocusedFrame: CGRect?
	
	@State private var keyboardFrame: CGRect = .zero
	
	private var focusedID: Binding<AnyHashable?> {
		externalFocusedID ?? $internalFocusedID
	}
	
	private var focusedFrame: Binding<CGRect?> {
		externalFocusedFrame ?? $internalFocusedFrame
	}
	
	func body(content: Content) -> some View {
		ScrollViewReader { proxy in
			ScrollView {
				content
					.environment(\.focusedIDBinding, focusedID)
					.environment(\.focusedFrameBinding, focusedFrame)
			}
			.onPreferenceChange(FieldFramePreferenceKey.self) { frames in
				if let id = focusedID.wrappedValue,
				   let frame = frames[id] {
					focusedFrame.wrappedValue = frame
					scrollIfNeeded(proxy: proxy)
				}
			}
			.onReceive(keyboardPublisher) { frame in
				keyboardFrame = frame
				scrollIfNeeded(proxy: proxy)
			}
		}
		.ignoresSafeArea(.keyboard)
	}
	
	private func scrollIfNeeded(proxy: ScrollViewProxy) {
		guard let id = focusedID.wrappedValue,
			  let fieldFrame = focusedFrame.wrappedValue,
			  keyboardFrame != .zero else { return }
		
		let keyboardTop = keyboardFrame.minY
		let fieldBottom = fieldFrame.maxY
		
		guard fieldBottom > keyboardTop else { return }
		
		withAnimation(.easeOut(duration: 0.25)) {
			proxy.scrollTo(id, anchor: .top)
		}
	}
	
	private var keyboardPublisher: AnyPublisher<CGRect, Never> {
		Publishers.Merge(
			NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
				.map { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero },
			NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
				.map { _ in CGRect.zero }
		)
		.eraseToAnyPublisher()
	}
}

extension View {
	func scrollAware() -> some View {
		modifier(ScrollAware(
			externalFocusedID: nil,
			externalFocusedFrame: nil
		))
	}
	
	func scrollAware(
		focusedID: Binding<AnyHashable?>,
		focusedFrame: Binding<CGRect?>
	) -> some View {
		modifier(ScrollAware(
			externalFocusedID: focusedID,
			externalFocusedFrame: focusedFrame
		))
	}
}

// MARK: - SwiftUI fieldAware

struct SwiftUIFieldAware: ViewModifier {
	@Environment(\.focusedIDBinding) private var focusedID
	
	@State private var internalID = UUID().uuidString
	@FocusState private var isFocused: Bool
	
	func body(content: Content) -> some View {
		content
			.id(internalID)
			.focused($isFocused)
			.background(
				GeometryReader { geo in
					Color.clear.preference(
						key: FieldFramePreferenceKey.self,
						value: [AnyHashable(internalID): geo.frame(in: .global)]
					)
				}
			)
			.onChange(of: isFocused) { focused in
				guard focused, let focusedID else { return }
				focusedID.wrappedValue = AnyHashable(internalID)
			}
	}
}

extension View {
	func fieldAware() -> some View {
		modifier(SwiftUIFieldAware())
	}
}

// MARK: - UIKit introspection helpers (Option B)

struct UIKitIntrospector: UIViewRepresentable {
	var onResolve: (UIView) -> Void
	
	func makeUIView(context: Context) -> UIView {
		let view = UIView()
		DispatchQueue.main.async {
			if let parent = view.superview {
				onResolve(parent)
			}
		}
		return view
	}
	
	func updateUIView(_ uiView: UIView, context: Context) {}
}

class ActionWrapper: NSObject {
	let action: () -> Void
	init(action: @escaping () -> Void) { self.action = action }
	@objc func invoke() { action() }
}

class TextViewDelegateWrapper: NSObject, UITextViewDelegate {
	let onBegin: () -> Void
	init(onBegin: @escaping () -> Void) { self.onBegin = onBegin }
	func textViewDidBeginEditing(_ textView: UITextView) { onBegin() }
}

class FirstResponderObserver: NSObject {
	weak var view: UIView?
	let onBecomeFirstResponder: () -> Void
	
	init(view: UIView, onBecomeFirstResponder: @escaping () -> Void) {
		self.view = view
		self.onBecomeFirstResponder = onBecomeFirstResponder
		super.init()
		view.addObserver(self,
						 forKeyPath: "isFirstResponder",
						 options: [.new],
						 context: nil)
	}
	
	override func observeValue(forKeyPath keyPath: String?,
							   of object: Any?,
							   change: [NSKeyValueChangeKey : Any]?,
							   context: UnsafeMutableRawPointer?) {
		guard keyPath == "isFirstResponder",
			  let view = object as? UIView,
			  view.isFirstResponder else { return }
		onBecomeFirstResponder()
	}
	
	deinit {
		view?.removeObserver(self, forKeyPath: "isFirstResponder")
	}
}

private enum AssocKeys {
	static var textFieldAction = UInt8.zero //"FieldAware_TextFieldAction"
	static var textViewDelegate = UInt8.zero //"FieldAware_TextViewDelegate"
	static var firstResponderObserver = UInt8.zero //"FieldAware_FirstResponderObserver"
}

// MARK: - UIKit fieldAware (Option B)

extension UIViewRepresentable {
	func fieldAware() -> some View {
		UIKitFieldAwareContainer(content: self)
	}
}

struct UIKitFieldAwareContainer<Content: UIViewRepresentable>: View {
	@Environment(\.focusedIDBinding) private var focusedID
	@Environment(\.focusedFrameBinding) private var focusedFrame
	
	@State private var id = UUID().uuidString
	let content: Content
	
	var body: some View {
		content
			.background(
				UIKitIntrospector { root in
					if let focusedID {
						attachFocusHandlers(to: root, focusedID: focusedID)
					}
				}
			)
			.background(
				GeometryReader { geo in
					Color.clear.preference(
						key: FieldFramePreferenceKey.self,
						value: [AnyHashable(id): geo.frame(in: .global)]
					)
				}
			)
	}
	
	private func attachFocusHandlers(to root: UIView,
									 focusedID: Binding<AnyHashable?>) {
		func walk(_ view: UIView) {
			// UITextField
			if let tf = view as? UITextField {
				let wrapper = ActionWrapper {
					focusedID.wrappedValue = AnyHashable(id)
				}
				objc_setAssociatedObject(tf,
										 &AssocKeys.textFieldAction,
										 wrapper,
										 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
				tf.addTarget(wrapper,
							 action: #selector(ActionWrapper.invoke),
							 for: .editingDidBegin)
			}
			
			// UITextView
			if let tv = view as? UITextView {
				let wrapper = TextViewDelegateWrapper {
					focusedID.wrappedValue = AnyHashable(id)
				}
				objc_setAssociatedObject(tv,
										 &AssocKeys.textViewDelegate,
										 wrapper,
										 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
				tv.delegate = wrapper
			}
			
			// ANY UIView that becomes first responder
			let observer = FirstResponderObserver(view: view) {
				focusedID.wrappedValue = AnyHashable(id)
			}
			objc_setAssociatedObject(view,
									 &AssocKeys.firstResponderObserver,
									 observer,
									 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
			
			for sub in view.subviews {
				walk(sub)
			}
		}
		
		walk(root)
	}
}

