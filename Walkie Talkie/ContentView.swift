import SwiftUI
import Combine

struct ContentView: View {
    @StateObject var networkManager = MeshRoutingEngine()
    
    @State private var userName: String = UIDevice.current.name
    @State private var peersToIgnore: String = ""
    @State private var isMeshStarted: Bool = false
    
    @State private var messageToSend: String = ""
    @State private var selectedTarget: String = "Everyone"
    @State private var receivedMessage: String = "No messages yet"
    
    var body: some View {
        VStack(spacing: 15) {
            
            // --- HEADER: SETUP ---
            if !isMeshStarted {
                VStack {
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
            
            // --- PEERS ---
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
            
            // --- LIVE DEBUG CONSOLE ---
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
            
            // --- MESSAGING UI ---
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
            
            // --- SENDING ---
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
            Spacer()
        }
        .padding(.top)
        .onAppear {
            networkManager.onPayloadReceived = { payloadData, originalSender, immediateRelayer, targetID in
                if let decodedText = String(data: payloadData, encoding: .utf8) {
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
