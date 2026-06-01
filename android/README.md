# voxa-sdk (Android, Kotlin)

Native Android SDK for Voxa Flow. Wraps the [LiveKit Android SDK](https://github.com/livekit/client-sdk-android) (media) + [socket.io-client (Java)](https://github.com/socketio/socket.io-client-java) (the Voxa realtime channel) + OkHttp (REST). Same unified API as every Voxa SDK — idiomatic Kotlin (Coroutines + Flow).

`minSdk 24`, `compileSdk 34`.

## Install

```kotlin
// settings.gradle.kts: google() + mavenCentral() repositories
dependencies {
    implementation("com.voxaflow:voxa-sdk:0.1.0") // (publish to Maven Central; until then use the module)
}
```

AndroidManifest permissions are merged from the library: `RECORD_AUDIO`, `CAMERA`, `INTERNET`, `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH_CONNECT`, `FOREGROUND_SERVICE`. Request runtime mic/camera permissions before `startCall`, and run a foreground service for ongoing calls.

## Quick start

```kotlin
import com.voxaflow.sdk.*

val client = VoxaClient(applicationContext, VoxaConfig(
    endpoint = "https://voxaflow.fastwheel.ai/api",
    token = serverMintedToken,              // from your backend — never an API secret
    onTokenRefresh = { myBackend.freshVoxaToken() }
))

client.connect()
lifecycleScope.launch { client.connectionState.collect { Log.d("voxa", "conn $it") } }
lifecycleScope.launch { client.transcript.collect { Log.d("voxa", "${it.speaker}: ${it.text}") } }

val call = client.startCall(video = true)
call.setMicEnabled(true)
// … later
call.end()

val chat = client.openChat(channel = "my-android-widget")
lifecycleScope.launch { client.messages.collect { /* render */ } }
chat.sendMessage("Hello")

client.disconnect()
```

## API (v0)

- `VoxaClient(context, config)` · `connect()` · `disconnect()` · `can(_)` · `profile`
- `startCall(callId?, video?, name?)` → `CallSession` (`setMicEnabled`/`setCameraEnabled`/`hold`/`resume`/`setMuted`/`end`, `lkRoom`)
- `openChat(conversationId?/channel?, …)` → `ChatSession` (`sendMessage`/`setTyping`/`markRead`)
- `setPresence(_)` (AGENT+)
- Flows: `connectionState`, `transcript`, `entities`, `formUpdates`, `messages`, `typing`, `presence`, `callStatus`

Auth: token-only (server-minted), transparent 401 refresh (REST + realtime). Capability gating from the JWT role. No PHI in Logcat/Crashlytics.

## Status (v0)

Core client, call, chat, Flow events, capability gating. Planned: Jetpack Compose views (`VoxaCallView`/`VoxaVideoRoom`/`VoxaChatView`/`VoxaCopilotPanel`) with the Midnight Intelligence theme; Android-critical native integration (AudioManager `MODE_IN_COMMUNICATION`, audio focus, foreground service, Bluetooth SCO/route changes, interruptions, proximity, PiP, FCM incoming-call); screen share (MediaProjection); Maven Central publish; sample app.

## Build

```sh
cd android
ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :voxa-sdk:assembleRelease
```

> Build needs the Android SDK (`platforms;android-34`, `build-tools;34.0.0`) + a Gradle 8.7–8.x wrapper (AGP 8.5.2). See the repo's `android/gradle/wrapper`.
