// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZoomMeetApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ZoomMeetApp",
            path: "Sources/ZoomMeetApp"
        )
    ]
)
