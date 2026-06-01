// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoxaSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "VoxaSDK", targets: ["VoxaSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/socketio/socket.io-client-swift.git", from: "16.1.0"),
    ],
    targets: [
        .target(
            name: "VoxaSDK",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift"),
                .product(name: "SocketIO", package: "socket.io-client-swift"),
            ]
        ),
        .testTarget(name: "VoxaSDKTests", dependencies: ["VoxaSDK"]),
    ]
)
