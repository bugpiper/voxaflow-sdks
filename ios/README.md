# VoxaSDK (iOS / macOS, Swift)

Native Swift SDK for Voxa Flow. Wraps the [LiveKit Swift SDK](https://github.com/livekit/client-sdk-swift) (media) + [Socket.IO](https://github.com/socketio/socket.io-client-swift) (the Voxa realtime channel). Same unified API as every Voxa SDK — idiomatic Swift (`async/await` + Combine).

iOS 15+ / macOS 12+.

## Install (Swift Package Manager)

```swift
.package(url: "https://github.com/bugpiper/voxaflow-sdks.git", from: "0.1.0")
// target dependency: .product(name: "VoxaSDK", package: "voxaflow-sdks")  // (ios/ subdir)
```

Add the required Info.plist keys in the integrating app: `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`; background modes `audio` (+ `voip` for incoming calls).

## Quick start

```swift
import VoxaSDK
import Combine

let client = VoxaClient(VoxaConfig(
    endpoint: "https://voxaflow.fastwheel.ai/api",
    token: serverMintedToken,                 // from your backend — never an API secret
    onTokenRefresh: { try await myBackend.freshVoxaToken() }
))

var bag = Set<AnyCancellable>()
client.connectionState.sink { print("conn", $0) }.store(in: &bag)
client.transcript.sink { print("\($0.speaker): \($0.text) final=\($0.isFinal)") }.store(in: &bag)

try await client.connect()
let call = try await client.startCall(video: true)
try await call.setMicEnabled(true)
// … later
await call.end()

let chat = try await client.openChat(channel: "my-ios-widget")
client.messages.sink { print($0.sender, $0.content, $0.isBot ? "[bot]" : "") }.store(in: &bag)
_ = try await chat.sendMessage("Hello")

client.disconnect()
```

## API (v0)

- `VoxaClient(config)` · `connect()` · `disconnect()` · `can(_:)` · `profile`
- `startCall(callId:video:name:)` → `CallSession` (`setMicEnabled`/`setCameraEnabled`/screen-share/`hold`/`resume`/`setMuted`/`end`, `lkRoom`)
- `openChat(conversationId:channel:…)` → `ChatSession` (`sendMessage`/`setTyping`/`markRead`)
- `setPresence(_:)` (AGENT+)
- Combine publishers: `connectionState`, `transcript`, `entities`, `formUpdates`, `messages`, `typing`, `presence`, `callStatus`

Auth: token-only (server-minted), transparent 401 refresh (REST + realtime). Capability gating from the JWT role. No PHI in `os_log`/Crashlytics.

## Status (v0)

Core client, call, chat, Combine events, capability gating. Planned: SwiftUI views (`VoxaCallView`/`VoxaVideoRoom`/`VoxaChatView`/`VoxaCopilotPanel`) with the Midnight Intelligence theme; iOS-critical native integration (AVAudioSession `.voiceChat`, CallKit, PushKit/VoIP, route/Bluetooth changes, interruptions, proximity, PiP, background modes); CocoaPods podspec; sample app.

## Build & validation status

Build for **iOS** with full Xcode:

```sh
cd ios && xcodebuild -scheme VoxaSDK -destination 'generic/platform=iOS' build
```

Validated here: the full non-LiveKit core — `VoxaClient`, `RestClient`, **`Realtime` (Socket.IO)**, `Models`, `Capabilities`, `ChatSession` — **compiles via `swift build`**. The LiveKit `CallSession` and the XCTest unit tests were **not** compiled in this environment: plain `swift build` targets macOS, where the LiveKit Swift module currently crashes the Swift 5.10 compiler (an AppKit `NSResponder`/`Sendable` serialization bug), and an iOS build / `swift test` needs **full Xcode** (only Command Line Tools were present). Build on a machine with Xcode to validate the call path + run tests.
