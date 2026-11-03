// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GitLabTracer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GitLabTracer", targets: ["GitLabTracer"]),
    ],
    targets: [
        .target(name: "GitLabTracerCore", path: "Sources/GitLabTracerCore"),
        .executableTarget(name: "GitLabTracer", dependencies: ["GitLabTracerCore"], path: "Sources/GitLabTracer"),
    ]
)
