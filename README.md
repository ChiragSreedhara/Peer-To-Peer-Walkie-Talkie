# Peer-To-Peer Walkie-Talkie

An iOS Peer-to-Peer Walkie-Talkie application built with Swift. It uses Apple's MPC framework for local networking and implements audio transmission with synchronous and asynchronous architectures, using OPUS codec for audio compression.

## How to Run

1. Install libraries needed - Run `brew install opus`
2. Open `Walkie Talkie.xcodeproj` in Xcode.
3. Select your target device
4. Build and Run the project
5. Grant the necessary permissions (Microphone and Local Network access) when asked on test device.

## Files

- **`MultipeerManager.swift`**: Handles peer discovery and connections using Apple `MultipeerConnectivity`

- **`MeshRoutingEngine.swift`**: Uses custom routing logic to support mesh networking with connected peers, allowing multi hopping of packets

- **`SyncAudioEngine.swift`, `AsyncAudioEngine.swift`**: Implementations of the audio processing pipelines, For synchronous and asynchronous to manage audio and audio buffers

- **`SyncContentView.swift`, `AsyncContentView.swift`**: The UI files for the different audio engine architectures 

- **`MetricsEngine.swift`, `MetricsReportView.swift`**: Tracks system performance metrics such as latency, packet loss, and jitter