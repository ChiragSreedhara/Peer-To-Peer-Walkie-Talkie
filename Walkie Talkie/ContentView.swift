import SwiftUI
import Combine
import AVFoundation

struct MeshMessage: Identifiable {
    let id = UUID()
    let sender: String
    let text: String?
    let audioData: Data?
}

struct ContentView: View {
    @StateObject var networkManager = MeshRoutingEngine()
    @StateObject var audioPipeline = AudioPipelineEngine()
    
    @State private var hasMicPermission = false
    @State private var showingPermissionAlert = false
    
    @State private var userName: String = ContentView.generateRandomCallsign()
    @State private var peersToIgnore: String = ""
    @State private var isMeshStarted: Bool = false
    
    @State private var messageToSend: String = ""
    @State private var selectedTarget: String = "Everyone"
    
    @State private var inboxMessages: [MeshMessage] = []
    
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
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            if inboxMessages.isEmpty {
                                Text("No messages yet")
                                    .foregroundColor(.gray)
                                    .padding()
                            }
                            
                            ForEach(inboxMessages) { msg in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(msg.sender)
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.blue)
                                        
                                        if let text = msg.text {
                                            Text(text)
                                        } else if let audioData = msg.audioData {
                                            Button {
                                                audioPipeline.playVoiceNote(audioData)
                                            } label: {
                                                HStack {
                                                    Image(systemName: "play.circle.fill")
                                                    Text("Voice Note (\(audioData.count / 1024) KB)")
                                                }
                                                .foregroundColor(.white)
                                                .padding(8)
                                                .background(Color.blue)
                                                .cornerRadius(8)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .frame(height: 200)
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
                    Text(audioPipeline.isTransmitting ? "Recording... (Max 3s)" : "Hold to talk")
                        .font(.caption)
                        .foregroundColor(audioPipeline.isTransmitting ? .red : .secondary)
                    
                    Circle()
                        .fill(audioPipeline.isTransmitting ? Color.red : Color.blue)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: audioPipeline.isPlaying ? "speaker.wave.2.fill" : "mic.fill")
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
                
                let senderLabel = originalSender == immediateRelayer ? originalSender : "\(originalSender) via \(immediateRelayer)"
                
                if let decodedText = String(data: payloadData, encoding: .utf8) {
                    let msg = MeshMessage(sender: senderLabel, text: decodedText, audioData: nil)
                    DispatchQueue.main.async { self.inboxMessages.append(msg) }
                } else {
                    let msg = MeshMessage(sender: senderLabel, text: nil, audioData: payloadData)
                    DispatchQueue.main.async { self.inboxMessages.append(msg) }
                }
            }
        }
    }
}
