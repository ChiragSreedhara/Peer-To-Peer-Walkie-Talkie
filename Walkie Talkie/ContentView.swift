import SwiftUI
import Combine
import AVFoundation

struct ContentView: View {
    @StateObject var networkManager = MeshRoutingEngine()
    @StateObject var audioPipeline = AudioPipelineEngine()
    @StateObject var metrics = MetricsEngine()

    @State private var showingReport = false
    
    @State private var hasMicPermission = false
    @State private var showingPermissionAlert = false
    
    @State private var userName: String = ContentView.generateRandomCallsign()
    @State private var peersToIgnore: String = ""
    @State private var isMeshStarted: Bool = false
    
    @State private var messageToSend: String = ""
    @State private var selectedTarget: String = "Everyone"
    @State private var receivedMessage: String = "No messages yet"
    
    static func generateRandomCallsign() -> String {
        let nouns = ["Falcon", "Wolf", "Hawk", "Bear", "Fox", "Raven", "Snake", "Echo"]
        let randomNum = Int.random(in: 1...9)
        
        return "\(nouns.randomElement()!)\(randomNum)"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                
                if !isMeshStarted {
                    VStack(spacing: 10) {
                        TextField("Enter your name", text: $userName)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("Simulate distance: Ignore peers (e.g. Alice, Bob)", text: $peersToIgnore)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Start Mesh") {
                            guard !userName.isEmpty else { return }
                            networkManager.startMesh(withName: userName, ignoring: peersToIgnore)
                            isMeshStarted = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 5)
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
                
                VStack {
                    Text("Connected Adjacent Peers: \(networkManager.connectedPeers.count)")
                        .font(.subheadline)
                        .foregroundColor(networkManager.connectedPeers.isEmpty ? .red : .green)
                    
                    HStack {
                        ForEach(networkManager.connectedPeers, id: \.self) { peerName in
                            Text("📱 \(peerName)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
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
                                    .foregroundColor(.white)
                                    .padding(.bottom, 1)
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
                
                VStack(alignment: .leading) {
                    Text("Chat Inbox:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(receivedMessage)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                
                VStack(spacing: 10) {
                    HStack {
                        Text("Send to:")
                        Picker("Target", selection: $selectedTarget) {
                            Text("Everyone").tag("Everyone")
                            ForEach(networkManager.connectedPeers, id: \.self) { peer in
                                Text(peer).tag(peer)
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    HStack {
                        TextField("Type a message...", text: $messageToSend)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Send") {
                            guard !messageToSend.isEmpty, isMeshStarted else { return }
                            if let rawBytes = messageToSend.data(using: .utf8) {
                                let target: String? = selectedTarget == "Everyone" ? nil : selectedTarget
                                networkManager.broadcast(payload: rawBytes, to: target)
                                messageToSend = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isMeshStarted)
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
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
                } else if let decodedText = String(data: payloadData, encoding: .utf8) {
                    metrics.recordTextReceived(senderID: originalSender, hopCount: hopCount, bytes: payloadData.count)
                    DispatchQueue.main.async {
                        if originalSender == immediateRelayer {
                            self.receivedMessage = "[\(originalSender)]: \(decodedText)"
                        } else {
                            self.receivedMessage = "[\(originalSender) via \(immediateRelayer)]: \(decodedText)"
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Live Metric Cell

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
