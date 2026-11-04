// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReplyAI",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ReplyAI", targets: ["ReplyAI"])],
    targets: [
        .target(name: "ReplyCore"),
        .executableTarget(name: "ReplyAI", dependencies: ["ReplyCore"]),
        .testTarget(name: "ReplyCoreTests", dependencies: ["ReplyCore"])
    ]
)
