import SwiftUI
import Combine
import AVFoundation

struct SyncContentView: View {
    @StateObject var networkManager = MeshRoutingEngine()
    @StateObject var audioPipeline = SyncAudioEngine()
    @StateObject var metrics = MetricsEngine()

    @State private var showingReport = false
    
    @State private var hasMicPermission = false
    @State private var showingPermissionAlert = false
    
    @State private var userName: String = SyncContentView.generateRandomCallsign()
    @State private var peersToIgnore: String = ""
    @State private var isMeshStarted: Bool = false
    
    static func generateRandomCallsign() -> String {
        let nouns = ["Falcon", "Wolf", "Hawk", "Bear", "Fox", "Raven", "Snake", "Echo"]
        let randomNum = Int.random(in: 1...9)
        return "\(nouns.randomElement()!)\(randomNum)"
    }

    var body: some View {
        ZStack {
            Color.wtBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        connectionStatusBadge
                        
                        if isPoweredOn {
                            dmSection
                            inboxSection
                        }

                        Spacer(minLength: 32)

                        pttSection

                        Spacer(minLength: 24)

                        debugSection

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            requestMicPermission()
            wireAudioPipeline()
        }
        .onChange(of: audioPipeline.isPlaying) { isPlaying in
            if !isPlaying {
                playingMessageID = nil
            }
        }
        .alert("Microphone Access Needed", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow microphone access in Settings to use Push to Talk.")
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isPoweredOn.toggle()
                        if isPoweredOn {
                            networkManager.startMesh(withName: userName, ignoring: peersToIgnore)
                        } else {
                            networkManager.stopMesh()
                        }
                    }
                    .padding(.horizontal)
                } else {
                    VStack {
                        Text("Operating as: \(userName)")
                            .font(.headline)
                            .foregroundColor(.green)
                        if !peersToIgnore.isEmpty {
                            Text("Ignoring: \(peersToIgnore)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        HStack(spacing: 12) {
                            Button("Clear Mesh") {
                                networkManager.clearMesh()
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)

                            Button("Disconnect") {
                                networkManager.stopMesh()
                                isMeshStarted = false
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(.top, 4)
                    }
                }

                if !isPoweredOn {
                    Text("Offline")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                }
            }

            Spacer()

            if isEditingName {
                HStack(spacing: 6) {
                    TextField("Your name", text: $editNameTemp)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(minWidth: 80)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.wtSurface)
                        .clipShape(Capsule())

                    Button {
                        let trimmed = editNameTemp.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { userName = trimmed }
                        isEditingName = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(wtGradient)
                    }
                }
            } else {
                Button {
                    guard !isPoweredOn else { return }
                    editNameTemp = userName
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isPoweredOn ? Color.wtGreen : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(userName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.wtSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.wtBorder, lineWidth: 1))
                }
            }
        }
    }

    private var connectionStatusBadge: some View {
        HStack(spacing: 8) {
            if !isPoweredOn {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 13))
                    .foregroundColor(.wtDimText)
            } else if !networkManager.connectedPeers.isEmpty {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.wtGreen)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .wtDimText))
                    .scaleEffect(0.75)
            }

            Text(isPoweredOn
                 ? (!networkManager.connectedPeers.isEmpty
                    ? "Connected · \(networkManager.connectedPeers.count) peers"
                    : "Searching for peers…")
                 : "Turn on to connect")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(!networkManager.connectedPeers.isEmpty ? .wtGreen : .wtDimText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(!networkManager.connectedPeers.isEmpty ? Color.wtGreen.opacity(0.10) : Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(!networkManager.connectedPeers.isEmpty ? Color.wtGreen.opacity(0.30) : Color.white.opacity(0.08), lineWidth: 1))
    }

    private var dmSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Target:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.wtPurple)
                
                // Live metrics bar
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        LiveMetricCell(label: "Sent", value: "\(metrics.audioSentCount)")
                        Divider().frame(height: 28)
                        LiveMetricCell(label: "Rcvd", value: "\(metrics.audioReceived.count)")
                        Divider().frame(height: 28)
                        LiveMetricCell(label: "Delivery", value: {
                            let byS = Dictionary(grouping: metrics.audioReceived, by: \.senderID)
                            guard !byS.isEmpty else { return "—" }
                            var totalExp = 0, totalRcv = 0
                            for (_, recs) in byS {
                                if let maxTS = recs.map(\.totalSent).max() {
                                    totalExp += Int(maxTS)
                                }
                                totalRcv += recs.count
                            }
                            guard totalExp > 0 else { return "—" }
                            return String(format: "%.1f%%", min(100.0, Double(totalRcv) / Double(totalExp) * 100))
                        }())
                        Divider().frame(height: 28)
                        LiveMetricCell(label: "Avg Lat", value: {
                            let lats = metrics.audioReceived.map(\.latencyMs)
                            guard !lats.isEmpty else { return "—" }
                            return String(format: "%.0f ms", lats.reduce(0, +) / Double(lats.count))
                        }())
                        Divider().frame(height: 28)
                        LiveMetricCell(label: "Avg Hops", value: {
                            guard !metrics.audioReceived.isEmpty else { return "—" }
                            let avg = Double(metrics.audioReceived.map(\.hopCount).reduce(0, +)) / Double(metrics.audioReceived.count)
                            return String(format: "%.1f", avg)
                        }())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                    Button(action: { showingReport = true }) {
                        Label("Session Report", systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                VStack(alignment: .leading) {
                    Text("System Logs:")
                        .font(.caption)
                        .bold()
                    
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(Array(networkManager.debugLogs.enumerated()), id: \.offset) { _, log in
                                Text(log)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color.wtGreen.opacity(0.75))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(8)
                    .frame(height: 150)
                }
                .padding(.horizontal)
                
                VStack(spacing: 8) {
                    Text(audioPipeline.isTransmitting ? "Release to stop" : "Hold to talk")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Circle()
                        .fill(audioPipeline.isTransmitting ? Color.red : Color.blue)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "mic.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        )
                        .shadow(color: audioPipeline.isTransmitting ? .red.opacity(0.5) : .blue.opacity(0.3),
                                radius: audioPipeline.isTransmitting ? 20 : 8)
                        .scaleEffect(audioPipeline.isTransmitting ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: audioPipeline.isTransmitting)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    guard hasMicPermission else {
                                        showingPermissionAlert = true
                                        return
                                    }
                                    guard isMeshStarted else { return }
                                    
                                    if !audioPipeline.isTransmitting {
                                        audioPipeline.startTransmitting()
                                    }
                                }
                                .onEnded { _ in
                                    audioPipeline.stopTransmitting()
                                }
                        )
                }
                .padding(.bottom, 30)
                
            }
            .padding(.top)
        }
        .sheet(isPresented: $showingReport) {
            MetricsReportView(report: metrics.generateReport(), onReset: { metrics.reset() })
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Microphone Access Required"),
                message: Text("Please enable microphone access in Settings to use the walkie-talkie."),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.hasMicPermission = granted
                }
            }
            
            audioPipeline.onAudioPacketReady = { packetData in
                if let packet = AudioPacket.deserialize(from: packetData) {
                    metrics.recordAudioSent()
                    _ = packet
                }
                networkManager.broadcast(payload: packetData, to: nil)
            }

            networkManager.onPayloadReceived = { payloadData, originalSender, immediateRelayer, targetID, hopCount in

                if let audioPacket = AudioPacket.deserialize(from: payloadData) {
                    audioPipeline.receiveAudioData(payloadData, from: originalSender)
                    metrics.recordAudioReceived(packet: audioPacket, hopCount: hopCount, bytes: payloadData.count)
                }
                .padding(10)
                .background(Color.wtSurface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.wtBorder, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func wireAudioPipeline() {
        audioPipeline.onAudioPacketReady = { data in
            let target: String? = selectedTarget == "Everyone" ? nil : selectedTarget
            networkManager.broadcast(payload: data, to: target)
        }

        networkManager.onPayloadReceived = { payload, senderID, relayer, targetID in
            let senderLabel = senderID == relayer ? senderID : "\(senderID) via \(relayer)"
            
            if let decodedText = String(data: payload, encoding: .utf8) {
                let msg = MeshMessage(sender: senderLabel, text: decodedText, audioData: nil)
                DispatchQueue.main.async { self.inboxMessages.insert(msg, at: 0) }
            } else {
                let msg = MeshMessage(sender: senderLabel, text: nil, audioData: payload)
                DispatchQueue.main.async { self.inboxMessages.insert(msg, at: 0) }
            }
        }
    }

    private func requestMicPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { self.hasMicPermission = granted }
        }
    }
}



private struct LiveMetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .bold()
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
