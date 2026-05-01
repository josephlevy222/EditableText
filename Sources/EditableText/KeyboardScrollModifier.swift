//
//  KeyboardScrollModifier.swift
//  EditableText
//
//  Created by Joseph Levy on 4/30/26.
//
import SwiftUI

struct KeyboardScrollModifier: ViewModifier {
	@State private var keyboardHeight: CGFloat = 0
	@ObservedObject var registry = FieldRegistry.shared
	
	func body(content: Content) -> some View {
		GeometryReader { geometry in
			ScrollViewReader { proxy in
				ScrollView {
					content
						.frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
						.padding(.bottom, keyboardHeight) // Keep your original padding logic
				}
				.onChange(of: keyboardHeight) { newHeight in
					// 4. If the keyboard is up and we have an active ID, scroll to it
					if newHeight > 0, let id = registry.activeID {
						withAnimation(.easeOut(duration: 0.25)) {
							proxy.scrollTo(id, anchor: .center)
						}
					}
				}
				
			}
		}
		.ignoresSafeArea(.keyboard) // Keep your existing ignore logic[cite: 1]
		// Notification listeners
		.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
			if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
				keyboardHeight = frame.cgRectValue.height
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
			keyboardHeight = 0
		}
	
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
			.onChange(of: isFocused) { focused in
				if focused {
					registry.activeID = id
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
