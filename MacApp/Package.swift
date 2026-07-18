// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalAgent",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "LocalAgent",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "LocalAgent",
            exclude: ["Info.plist", "LocalAgent.entitlements", "Assets.xcassets"]
        ),
    ]
)
