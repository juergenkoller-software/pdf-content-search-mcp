// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "pdf-content-search-mcp",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "pdf-content-search-mcp",
            path: "Sources/pdf-content-search-mcp"
        )
    ]
)
