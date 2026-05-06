//
//  KeyboardScrollModifier.swift
//  EditableText
//
//  Created by Joseph Levy on 4/30/26.
//
//
//  KeyboardHeightPublisher.swift
//  KeyboardAvoidanceSwiftUI
//
//  Created by Vadim Bulavin on 3/27/20.
//  Copyright © 2020 Vadim Bulavin. All rights reserved.
//

import Combine
import UIKit

extension Publishers {
	static var keyboardHeight: AnyPublisher<CGFloat, Never> {
		let willShow = NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
			.map { $0.keyboardHeight }
		
		let willHide = NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
			.map { _ in CGFloat(0) }
		
		return MergeMany(willShow, willHide)
			.eraseToAnyPublisher()
	}
}

extension Notification {
	var keyboardHeight: CGFloat {
		return (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
	}
}
//
//  UIResponder+Current.swift
//  KeyboardAvoidanceSwiftUI
//
//  Created by Vadim Bulavin on 3/27/20.
//  Copyright © 2020 Vadim Bulavin. All rights reserved.
//

// From https://stackoverflow.com/a/14135456/6870041
extension UIResponder {
	static var currentFirstResponder: UIResponder? {
		_currentFirstResponder = nil
		UIApplication.shared.sendAction(#selector(UIResponder.findFirstResponder(_:)), to: nil, from: nil, for: nil)
		return _currentFirstResponder
	}
	
	private static weak var _currentFirstResponder: UIResponder?
	
	@objc private func findFirstResponder(_ sender: Any) {
		UIResponder._currentFirstResponder = self
	}
	
	var globalFrame: CGRect? {
		guard let view = self as? UIView else { return nil }
		return view.superview?.convert(view.frame, to: nil)
	}
}

import SwiftUI

struct KeyboardScrollModifier: ViewModifier {
	@State private var keyboardHeight: CGFloat = 0
	@State private var bottomPadding: CGFloat = 0
	//@ObservedObject var registry = FieldRegistry.shared
	
	func body(content: Content) -> some View {
		GeometryReader { geometry in
			ScrollViewReader { proxy in
				ScrollView {
					VStack(spacing: 0) {
						content
							.frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
							.padding(.bottom, self.keyboardHeight)
							.onReceive(Publishers.keyboardHeight) { keyboardHeight in
								self.keyboardHeight = keyboardHeight
								let keyboardTop = geometry.frame(in: .global).height - keyboardHeight
								let focusedTextInputBottom = UIResponder.currentFirstResponder?.globalFrame?.maxY ?? 0
								bottomPadding = max(0, focusedTextInputBottom - keyboardTop - geometry.safeAreaInsets.bottom)
								print("kH, kT, fTIB, bP", keyboardHeight, keyboardTop, focusedTextInputBottom, bottomPadding)
							}
							.animation(.easeOut, value: 0.16)
						Color.red.frame(height: 1).offset(y: -keyboardHeight+bottomPadding).id("bottom")
							.padding(.bottom, -1)
					}
				}
				.onChange(of: bottomPadding) { newHeight in
					//if newHeight > 0, let id = registry.activeID {
						/// A slightly longer delay helps ensure the swap from Text to RichTextEditor is complete so the ID is attached to the new view.
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
							withAnimation(.easeInOut(duration: 5.3)) {
								/// Using .top is more predictable than .center when the bottom half of the screen is "invisible."
								proxy.scrollTo("bottom", anchor: .top)
							}
						}
					//}
				}
			}
		}
		//.ignoresSafeArea(.keyboard) // Keep your existing ignore logic[cite: 1]
//		// Notification listeners
//		.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
//			if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
//				keyboardHeight = frame.cgRectValue.height //+ 60
//			}
//		}
//		.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
//			keyboardHeight = 0
//		}
	
	}
}
	
extension View {
	public func keyboardAwareScrolling() -> some View {
		modifier(KeyboardScrollModifier())
	}
}

class FieldRegistry: ObservableObject {
	static let shared = FieldRegistry() // The Singleton instance
	@Published var activeID: String?
	// Private init ensures no one else can create a new registry
	private init() {}
}

struct KeyboardFieldModifier: ViewModifier {
	@ObservedObject var registry = FieldRegistry.shared
	@State private var id = UUID().uuidString // Stable identity
	@FocusState private var isFocused: Bool // Handles native focus
	
	func body(content: Content) -> some View {
		content
			.focused($isFocused) // Syncs with native keyboard focus
			.id(id)              // Anchors the view for ScrollViewReader
			.onChange(of: isFocused) { focus in
				print("\(id) Focus Changed: \(isFocused)")
				if focus {
					registry.activeID = id
				} else {
					if registry.activeID == id {
						print("Successfully cleared the registry!")
						registry.activeID = nil
					}
				}
			}
			// For custom fields (like your RichEditText swap), a tap gesture ensures the ID is registered.
			.simultaneousGesture(TapGesture().onEnded {
				registry.activeID = id
			})
	}
}

extension View {
	public func registerField() -> some View {
		self.modifier(KeyboardFieldModifier())
	}
}

#if false
// Copilot Versions
import SwiftUI
import Combine

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

// FieldAware (SwiftUI + UIKit‑friendly)
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
					Color.clear
						.preference(
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


//  ScrollAware (keyboard + “only when obscured” + nested support)
struct ScrollAware: ViewModifier {
	// Optional external bindings
	var externalFocusedID: Binding<AnyHashable?>?
	var externalFocusedFrame: Binding<CGRect?>?
	
	// Internal state if externals are nil
	@State private var internalFocusedID: AnyHashable?
	@State private var internalFocusedFrame: CGRect?
	
	@State private var keyboardFrame: CGRect = .zero
	@State private var containerFrame: CGRect = .zero
	
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
			.background(
				GeometryReader { geo in
					Color.clear
						.onAppear { containerFrame = geo.frame(in: .global) }
						.onChange(of: geo.frame(in: .global)) { containerFrame = $0 }
				}
			)
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

// MARK: - UIKit wrapper + unified fieldAware for UIViewRepresentable

struct UIKitFieldWrapper<Content: UIViewRepresentable>: UIViewRepresentable {
	let content: Content
	let id: AnyHashable
	@Binding var focusedID: AnyHashable?
	@Binding var focusedFrame: CGRect?
	
	class Coordinator: NSObject, UITextViewDelegate {
		var parent: UIKitFieldWrapper
		
		init(parent: UIKitFieldWrapper) {
			self.parent = parent
		}
		
		@objc func didBeginEditing(_ sender: UIView) {
			parent.focusedID = parent.id
		}
		
		// UITextViewDelegate
		func textViewDidBeginEditing(_ textView: UITextView) {
			parent.focusedID = parent.id
		}
	}
	
	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}
	
	func makeUIView(context: Context) -> UIView {
		let container = UIView()
		
		let hosting = UIHostingController(rootView: content)
		let hostedView = hosting.view!
		hostedView.backgroundColor = .clear
		hostedView.translatesAutoresizingMaskIntoConstraints = false
		
		container.addSubview(hostedView)
		NSLayoutConstraint.activate([
			hostedView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			hostedView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			hostedView.topAnchor.constraint(equalTo: container.topAnchor),
			hostedView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
		])
		
		attachFocusHandlers(to: hostedView, coordinator: context.coordinator)
		
		return container
	}
	
	func updateUIView(_ uiView: UIView, context: Context) {
		guard
			let hostingView = uiView.subviews.first,
			let hosting = hostingView.next as? UIHostingController<Content>
		else { return }
		
		hosting.rootView = content
	}
	
	private func attachFocusHandlers(to view: UIView, coordinator: Coordinator) {
		if let tf = view as? UITextField {
			tf.addTarget(coordinator,
						 action: #selector(Coordinator.didBeginEditing(_:)),
						 for: .editingDidBegin)
		}
		
		if let tv = view as? UITextView {
			tv.delegate = coordinator
		}
		
		for sub in view.subviews {
			attachFocusHandlers(to: sub, coordinator: coordinator)
		}
	}
}

// MARK: - SwiftUI container for UIKitFieldWrapper

struct UIKitFieldContainer<Content: UIViewRepresentable>: View {
	@Environment(\.focusedIDBinding) private var focusedID
	@Environment(\.focusedFrameBinding) private var focusedFrame
	
	@State private var id = UUID().uuidString
	let content: Content
	
	var body: some View {
		if let focusedID, let focusedFrame {
			UIKitFieldWrapper(
				content: content,
				id: AnyHashable(id),
				focusedID: focusedID,
				focusedFrame: focusedFrame
			)
			.background(
				GeometryReader { geo in
					Color.clear
						.preference(
							key: FieldFramePreferenceKey.self,
							value: [AnyHashable(id): geo.frame(in: .global)]
						)
				}
			)
		} else {
			// If not inside ScrollAware, just render normally
			content
		}
	}
}

// MARK: - Unified name for UIKit fields

extension UIViewRepresentable {
	func fieldAware() -> some View {
		UIKitFieldContainer(content: self)
	}
}

// Example usage
struct DemoView: View {
	@State private var name = ""
	@State private var bio = ""
	@State private var username = ""
	
	var body: some View {
		VStack(spacing: 16) {
			Spacer()
			TextField("Name", text: $name)
				.textFieldStyle(.roundedBorder)
				.fieldAware()          // SwiftUI
			
			TextEditor(text: $bio)
				.frame(height: 120)
				.border(Color.gray)
				.fieldAware()          // SwiftUI
			
			UIKitTextField(text: $username)
				.fieldAware()          // UIKit
		}
		.padding()
		.scrollAware()
	}
}

// Simple UIKitTextField for demo
struct UIKitTextField: UIViewRepresentable {
	@Binding var text: String
	
	func makeUIView(context: Context) -> UITextField {
		let tf = UITextField()
		tf.borderStyle = .roundedRect
		tf.addTarget(context.coordinator,
					 action: #selector(Coordinator.changed(_:)),
					 for: .editingChanged)
		return tf
	}
	
	func updateUIView(_ uiView: UITextField, context: Context) {
		uiView.text = text
	}
	
	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}
	
	class Coordinator: NSObject {
		var parent: UIKitTextField
		init(parent: UIKitTextField) { self.parent = parent }
		
		@objc func changed(_ sender: UITextField) {
			parent.text = sender.text ?? ""
		}
	}
}

#Preview {
	DemoView()
}

// Introspect version
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

extension UIViewRepresentable {
	func uifieldAware() -> some View {
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
			.background(UIKitIntrospector { root in
				attachFocusHandlers(to: root)
			})
			.background(
				GeometryReader { geo in
					Color.clear.preference(
						key: FieldFramePreferenceKey.self,
						value: [AnyHashable(id): geo.frame(in: .global)]
					)
				}
			)
	}
	
	private func attachFocusHandlers(to root: UIView) {
		guard let focusedID else { return }
		
		func walk(_ view: UIView) {
			if let tf = view as? UITextField {
				tf.addTarget(
					ActionWrapper { focusedID.wrappedValue = AnyHashable(id) },
					action: #selector(ActionWrapper.invoke),
					for: .editingDidBegin
				)
			}
			
			if let tv = view as? UITextView {
				tv.delegate = TextViewDelegateWrapper { focusedID.wrappedValue = AnyHashable(id) }
			}
			
			for sub in view.subviews { walk(sub) }
		}
		
		walk(root)
	}
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
#endif
