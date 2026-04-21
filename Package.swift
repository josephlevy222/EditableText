// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

fileprivate func repo(_ repo: String) -> String {
	return "https://github.com/josephlevy222/" + repo + ".git"
}

let package = Package(
    name: "EditableText",
	platforms: [.iOS("15.5"),.macOS(.v12)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EditableText",
            targets: ["EditableText"]),
    ],
	dependencies: [ .package(url: repo("Utilities"), branch: "main"), ],
	
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "EditableText",
			dependencies: ["Utilities"],
			resources: [
				.process("sound56.wav")]
		),
		.testTarget(
			name: "EditableTextTests",
			dependencies: ["EditableText"]),
	]
)
