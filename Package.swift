// swift-tools-version: 6.2
import PackageDescription

var products: [Product] = [
    .library(name: "StackbarCore", targets: ["StackbarCore"]),
]

var targets: [Target] = [
    .target(name: "StackbarCore", exclude: ["CLAUDE.md"]),
    .testTarget(name: "StackbarCoreTests", dependencies: ["StackbarCore"]),
]

// The app needs AppKit, so it only exists in the manifest on macOS. This keeps `swift build`
// and `swift test` green in the Linux devcontainer. No other platform conditionals allowed.
#if os(macOS)
products.append(.executable(name: "Stackbar", targets: ["StackbarApp"]))
targets.append(
    .executableTarget(name: "StackbarApp", dependencies: ["StackbarCore"], exclude: ["CLAUDE.md"])
)
#endif

let package = Package(
    name: "Stackbar",
    platforms: [.macOS(.v26)],
    products: products,
    targets: targets
)
