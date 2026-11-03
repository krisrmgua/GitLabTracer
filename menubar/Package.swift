// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PipelineTracer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PipelineTracer", targets: ["PipelineTracer"]),
    ],
    targets: [
        .target(name: "PipelineTracerCore", path: "Sources/PipelineTracerCore"),
        .executableTarget(name: "PipelineTracer", dependencies: ["PipelineTracerCore"], path: "Sources/PipelineTracer"),
    ]
)
