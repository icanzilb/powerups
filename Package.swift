// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "powerups",
	platforms: [
		.macOS(.v11)
	],
    targets: [
        .executableTarget(
            name: "powerups"
        ),
        .testTarget(
            name: "powerupsTests",
            dependencies: ["powerups"]
        )
    ]
)
