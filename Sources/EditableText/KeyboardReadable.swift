//
//  KeyboardReadable.swift
//
//
//  Created by Joseph Levy on 9/2/24.
//  from StackOverflow https://stackoverflow.com/questions/65784294/how-to-detect-if-keyboard-is-present-in-swiftui
//  Max gave this answer based on George

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
