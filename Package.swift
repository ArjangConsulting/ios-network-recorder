// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "APITraceSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "APITraceCore", targets: ["APITraceCore"]),
        .library(name: "APITraceDebug", targets: ["APITraceDebug"]),
        .library(name: "APITraceNoop", targets: ["APITraceNoop"])
    ],
    targets: [
        .target(name: "APITraceCore"),
        .target(name: "APITraceDebug", dependencies: ["APITraceCore"]),
        .target(name: "APITraceNoop", dependencies: ["APITraceCore"]),
        .testTarget(name: "APITraceCoreTests", dependencies: ["APITraceCore"])
    ]
)
