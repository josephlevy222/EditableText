//
//  KeyboardReadable.swift
//
//
//  Created by Joseph Levy on 9/2/24.
//  from StackOverflow https://stackoverflow.com/questions/65784294/how-to-detect-if-keyboard-is-present-in-swiftui
//  Max gave this answer based on George
#if false // the previous try
import Combine
import SwiftUI
/// Publisher to read keyboard changes.

extension View {
	
	var keyboardPublisher: AnyPublisher<Bool, Never> {
		Publishers
			.Merge(
				NotificationCenter
					.default
					.publisher(for: UIResponder.keyboardDidShowNotification)
					.map { _ in true },
				NotificationCenter
					.default
					.publisher(for: UIResponder.keyboardWillHideNotification)
					.map { _ in false })
			.debounce(for: .seconds(0.1), scheduler: RunLoop.main)
			.eraseToAnyPublisher()
	}
}



final class FirstResponderTracker: UIView {
	static weak var current: UIView?
	
	override func becomeFirstResponder() -> Bool {
		FirstResponderTracker.current = self
		return super.becomeFirstResponder()
	}
	
	override func resignFirstResponder() -> Bool {
		if FirstResponderTracker.current === self {
			FirstResponderTracker.current = nil
		}
		return super.resignFirstResponder()
	}
}

struct FirstResponderTrackingView: UIViewRepresentable {
	func makeUIView(context: Context) -> UIView {
		let view = FirstResponderTracker()
		view.isUserInteractionEnabled = false
		view.backgroundColor = .clear
		return view
	}
	
	func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor func firstResponderFrame() -> CGRect? {
	guard let view = FirstResponderTracker.current else { return nil }
	return view.convert(view.bounds, to: nil)
}

@MainActor
final class KeyboardObserver: ObservableObject {
	@Published var height: CGFloat = 0
	
	nonisolated(unsafe) private var showObserver: Any?
	nonisolated(unsafe) private var hideObserver: Any?
	
	init() {
		showObserver = NotificationCenter.default.addObserver(
			forName: UIResponder.keyboardWillShowNotification,
			object: nil,
			queue: .main
		) { notification in
			// Extract newHeight you need from `notification` here
			let newHeight: CGFloat =
			if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
				frame.cgRectValue.height
			} else {
				0
			}
			
			// Then hop to the main actor with only plain data
			Task { @MainActor in self.height = newHeight }
		}
		
		hideObserver = NotificationCenter.default.addObserver(
			forName: UIResponder.keyboardWillHideNotification,
			object: nil,
			queue: .main
		) { _ in
			Task { @MainActor in
				self.height = 0
			}
		}
	}
	
	deinit {
		if let showObserver { NotificationCenter.default.removeObserver(showObserver) }
		if let hideObserver { NotificationCenter.default.removeObserver(hideObserver) }
	}
}

private struct DynamicAnchorKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = nextValue()
	}
}

struct DynamicKeyboardAwareModifier: ViewModifier {
	@StateObject private var keyboard = KeyboardObserver()
	@State private var anchorOffset: CGFloat = 0
	
	private let anchorID = "keyboard-dynamic-anchor"
	
	func body(content: Content) -> some View {
		GeometryReader { outerGeo in
			ScrollViewReader { proxy in
				ScrollView {
					VStack(spacing: 0) {
						ZStack(alignment: .topLeading) {
							content
							
							// Tracks UIKit first responder
							FirstResponderTrackingView()
						}
						.background(
							GeometryReader { geo in
								Color.clear
									.preference(
										key: DynamicAnchorKey.self,
										value: computeAnchorOffset(container: geo)
									)
							}
						)
						
						// Dynamic anchor in vertical layout
						Color.clear
							.frame(height: 0)
							.id(anchorID)
							.alignmentGuide(.top) { _ in
								-anchorOffset
							}
					}
					.frame(minHeight: outerGeo.size.height)
					.padding(.bottom, keyboard.height > 0 ? keyboard.height : 20)
				}
				.onPreferenceChange(DynamicAnchorKey.self) { newOffset in
					anchorOffset = newOffset
				}
				.onChange(of: keyboard.height) { newHeight in
					guard newHeight > 0 else { return }
					
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
						scrollToFirstResponderIfNeeded(proxy: proxy)
					}
				}
			}
		}
		.ignoresSafeArea(.keyboard)
	}
	
	private func computeAnchorOffset(container geo: GeometryProxy) -> CGFloat {
		guard let frame = firstResponderFrame() else { return 0 }
		
		// Convert global Y into container’s coordinate space
		let containerFrame = geo.frame(in: .global)
		let localY = frame.minY - containerFrame.minY
		return localY
	}
	
	private func scrollToFirstResponderIfNeeded(proxy: ScrollViewProxy) {
		guard let frame = firstResponderFrame() else { return }
		
		let keyboardTop = UIScreen.main.bounds.height - keyboard.height
		let fieldBottom = frame.maxY
		
		guard fieldBottom > keyboardTop else { return }
		
		withAnimation(.easeInOut(duration: 0.3)) {
			proxy.scrollTo(anchorID, anchor: .top)
		}
	}
}

extension View {
	public func keyboardAwareDynamic() -> some View {
		modifier(DynamicKeyboardAwareModifier())
	}
}

//struct KeyboardAwareModifier: ViewModifier {
//	@StateObject private var keyboard = KeyboardObserver()
//
//	private let anchorID = "keyboard-anchor"
//
//	func body(content: Content) -> some View {
//		GeometryReader { outerGeo in
//			ScrollViewReader { proxy in
//				ScrollView {
//					VStack(alignment: .leading, spacing: 0) {
//						ZStack(alignment: .topLeading) {
//							content
//							FirstResponderTrackingView()
//						}
//						.background(
//							GeometryReader { geo in
//								Color.clear
//									.preference(key: FirstResponderFrameKey.self,
//												value: geo.frame(in: .global))
//							}
//						)
//
//						// Dynamic anchor
//						Color.clear
//							.frame(height: 0)
//							.id("dynamic-anchor")
//							.alignmentGuide(.top) { _ in
//								dynamicAnchorOffset   // ← computed from first responder frame
//							}
//					}
//					.frame(minHeight: outerGeo.size.height)
//					.padding(.bottom, keyboard.height > 0 ? keyboard.height : 20)
//				}
//				.onChange(of: keyboard.height) { newHeight in
//					guard newHeight > 0 else { return }
//
//					DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
//						scrollToFirstResponderIfNeeded(proxy: proxy)
//					}
//				}
//			}
//		}
//		.ignoresSafeArea(.keyboard)
//	}
//
//	private func scrollToFirstResponderIfNeeded(proxy: ScrollViewProxy) {
//		guard let frame = firstResponderFrame() else { return }
//
//		let keyboardTop = UIScreen.main.bounds.height - keyboard.height
//		let fieldBottom = frame.maxY
//
//		if fieldBottom > keyboardTop {
//			withAnimation(.easeInOut(duration: 0.3)) {
//				proxy.scrollTo(anchorID, anchor: .top)
//			}
//		}
//	}
//}
//
//extension View {
//	public func keyboardAware() -> some View {
//		modifier(KeyboardAwareModifier())
//	}
//}

struct ExampleForm: View {
	@State private var name = ""
	@State private var notes = ""
	
	var body: some View {
		VStack {
			Text("Profile")
				.font(.largeTitle)
				.padding(.top)
			
			TextField("Name", text: $name)
				.textFieldStyle(.roundedBorder)
				.padding()
			
			TextEditor(text: $notes)
				.frame(height: 200)
				.padding()
				.overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray))
		}
		.keyboardAwareDynamic()   // ← That’s it
		.padding()
	}
}

#endif
