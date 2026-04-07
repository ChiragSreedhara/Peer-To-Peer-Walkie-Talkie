import SwiftUI
import Combine
import AVFoundation

struct ContentView: View {
    @StateObject var networkManager = MeshRoutingEngine()
    @StateObject var audioPipeline = AudioPipelineEngine()
    
    @State private var hasMicPermission = false
    @State private var showingPermissionAlert = false
    
    // NEW: We call our random generator right here!
    @State private var userName: String = ContentView.generateRandomCallsign()
    @State private var peersToIgnore: String = ""
    @State private var isMeshStarted: Bool = false
    
    @State private var messageToSend: String = ""
    @State private var selectedTarget: String = "Everyone"
    @State private var receivedMessage: String = "No messages yet"
    
    static func generateRandomCallsign() -> String {
        let nouns = ["Falcon", "Wolf", "Hawk", "Bear", "Fox", "Raven", "Snake", "Echo"]
        let randomNum = Int.random(in: 10...99)
        
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
                
                VStack(alignment: .leading) {
                    Text("System Logs:")
                        .font(.caption)
                        .bold()
                    
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(networkManager.debugLogs, id: \.self) { log in
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
                networkManager.broadcast(payload: packetData, to: nil)
            }
            
            networkManager.onPayloadReceived = { payloadData, originalSender, immediateRelayer, targetID in
                
                if let _ = AudioPacket.deserialize(from: payloadData) {
                    audioPipeline.receiveAudioData(payloadData, from: originalSender)
                }
                else if let decodedText = String(data: payloadData, encoding: .utf8) {
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
