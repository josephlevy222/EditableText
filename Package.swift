// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EditableText",
	platforms: [.iOS("15.5"),.macOS(.v12)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EditableText",
            targets: ["EditableText"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "EditableText",
			resources: [
				.process("sound56.wav")]
		),
		.testTarget(
			name: "EditableTextTests",
			dependencies: ["EditableText"]),
	]
)
