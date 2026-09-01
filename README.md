# RecordScreen

Native SwiftUI project for an iPhone camera publisher and a Mac receiver.

## Targets

| Target | Responsibility |
|---|---|
| `RecordScreeniOS` | Rear-camera WebRTC publisher, Bonjour discovery, TCP signaling |
| `RecordScreenMac` | Bonjour receiver, TCP signaling, live WebRTC Metal preview |
| `RecordScreenShared` | Connection state, signaling contracts, design tokens, reusable styles |

The project resolves [stasel/WebRTC](https://github.com/stasel/WebRTC.git) at exactly
version `152.0.0`. The connection uses newline-delimited Codable messages over the
existing local TCP control connection for `hello`/`ack`, SDP, and ICE candidates.

## Connect and run

1. Open `RecordScreen.xcodeproj` in Xcode and resolve package dependencies.
2. Run `RecordScreenMac`, then select **Start Receiver**. Its Bonjour service becomes
   visible on the local network.
3. Run `RecordScreeniOS` on a physical iPhone, allow camera and local-network access,
   and select **Connect** beside the Mac receiver.
4. Wait for the connection status to confirm the TCP handshake, then select
   **Start Streaming**. The iPhone offers a WebRTC session and the Mac shows the
   received video in its preview area.

This first WebRTC implementation is **LAN-only**, **video-only**, and has **no
recording** yet. It deliberately configures no public STUN/TURN server; peers exchange
host ICE candidates on the same local network. Audio, remote-network connectivity, and
recording are future work.

## Notes

- iOS uses the rear camera through `RTCCameraVideoCapturer`, so a physical device is
  required for a real camera stream.
- The Mac UI's recording controls are intentionally absent until an `AVAssetWriter`
  recording pipeline is implemented.
