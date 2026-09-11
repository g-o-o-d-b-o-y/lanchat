# LANChatDemo — iOS + macOS

A minimal peer-to-peer-ish LAN chat where either an iPhone or a Mac can be the temporary server. The host advertises a Bonjour service; the QR code contains the Bonjour service identity rather than an IP address. The joining device scans it, browses Bonjour, resolves the endpoint, and connects over TCP using Network.framework.


## Current platform check (September 11, 2026)

Apple has Xcode 27 RC, iOS 27.0 RC, and macOS 27.0 RC available. The sample intentionally uses APIs that remain supported on those SDKs while keeping a deployment target of iOS 17+/macOS 14+ practical.

## Recommended Xcode setup

Create two SwiftUI app targets in one Xcode project:

- `LANChat-iOS` — iOS 17+ (or newer)
- `LANChat-macOS` — macOS 14+ (or newer)

Use Swift 6 language mode if your project supports it. Add all files under `Shared/` to both targets. Add `iOS/` files only to the iOS target and `macOS/` files only to the macOS target.

The networking code deliberately uses the mature `NWListener` / `NWBrowser` / `NWConnection` API. It continues to work on current systems and keeps the sample compatible with older OS versions. If you target only iOS/macOS 26+, you can later migrate this layer to the newer structured-concurrency Network APIs.

## Info.plist — iOS

Add:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan a LAN Chat QR code to connect to a nearby chat.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Find and connect to LAN Chat devices on your local Wi‑Fi network.</string>
<key>NSBonjourServices</key>
<array>
    <string>_lanchat._tcp</string>
</array>
```

## Info.plist — macOS

Add:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan a LAN Chat QR code to connect to a nearby chat.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Find and connect to LAN Chat devices on your local network.</string>
<key>NSBonjourServices</key>
<array>
    <string>_lanchat._tcp</string>
</array>
```

For a sandboxed macOS app, enable **Signing & Capabilities → App Sandbox → Network → Incoming Connections (Server)** and **Outgoing Connections (Client)**. Enable camera access as required by your target/capabilities.

## How it works

1. Tap **Get QR** on either iPhone or Mac.
2. That device starts an `NWListener` and advertises `_lanchat._tcp` using Bonjour.
3. The QR encodes a small versioned invitation containing the Bonjour service name and type.
4. On another device, tap **Scan QR**.
5. The client uses `NWBrowser` to find that exact Bonjour instance, then creates an `NWConnection` directly from the returned service endpoint.
6. Messages are JSON, prefixed by a 4-byte big-endian payload length. A host broadcasts received chat messages to all connected clients.

6b. Attachments (images, videos, documents) are attached from the composer's paperclip menu — via the Photos picker or the file importer. Files travel base64-encoded inside the JSON frame and are capped at 15 MB each (32 MB frame limit on the receiving side).

**No camera? No problem.** The invitation is just a short link (`lanchat://join?data=…`). Tap **Copy invitation link** under any QR code, then paste it into the join sheet's text field (shown below the camera preview on macOS) instead of scanning. macOS scanning uses Vision's `VNDetectBarcodesRequest` on live camera frames, so it also works with cameras that expose no QR metadata types (e.g. Continuity Camera).

## Test matrix

Test on physical devices, not only Simulator:

- iPhone host → iPhone client
- iPhone host → Mac client
- Mac host → iPhone client
- Mac host → Mac client
- 1 host + 2+ clients to verify broadcast

All devices should be on the same LAN/Wi‑Fi and local-network access must be allowed.

## Important iOS limitation

An ordinary iOS app is not an always-on server. This sample is suitable while the app is active in the foreground. Once iOS suspends the app in the background, you should expect the listener and chat to stop being reliably available. A Mac is the better choice for a persistent local server.

## Production hardening ideas

This is intentionally a small prototype. Before using it for anything sensitive, add:

- TLS with a per-session identity or authenticated key exchange.
- An invitation secret/token in the QR and a challenge during connection setup.
- Limits for message rate, number of clients, and total buffered bytes.
- Heartbeats/timeouts and explicit reconnect state.
- Persistence if message history matters.
- Better identity/nickname handling.
- Tests for framing, malformed input, disconnects, and multiple simultaneous clients.

## Why Swift instead of Go/Rust for this experiment?

For an iOS/macOS-only LAN feature, Swift + Network.framework has the least integration cost and best platform fit: Bonjour, privacy prompts, lifecycle, SwiftUI, and Apple networking APIs are all native. A Go/Rust core starts to make sense if the same protocol/server must run headlessly on Linux/Windows/NAS, you need a long-lived daemon, or substantial cross-platform networking/business logic is shared. On iOS, embedding a custom Go/Rust networking runtime does not remove iOS background-execution restrictions.
