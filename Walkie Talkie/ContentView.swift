import SwiftUI
import MultipeerConnectivity
import Combine
import AVFoundation


struct ContentView: View {
    @StateObject var networkManager = MeshRoutingEngine()
    @StateObject var audioPipeline = AudioPipelineEngine()
    
    @State private var hasMicPermission = false
    @State private var showingPermissionAlert = false
    
    
    @State private var messageToSend: String = ""
    @State private var receivedMessage: String = "No messages yet"
    
    var body: some View {
        VStack(spacing: 30) {
            Text("ui for layer 4 test")
                .font(.headline)
            
            VStack {
                Text("Connected Peers: \(networkManager.connectedPeers.count)")
                    .font(.headline)
                    .foregroundColor(networkManager.connectedPeers.isEmpty ? .red : .green)
                
                ForEach(networkManager.connectedPeers, id: \.self) { peerName in
                    Text("📱 \(peerName)")
                        .foregroundColor(.blue)
                }
            }
            
            VStack(alignment: .leading) {
                Text("Received Message:")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(receivedMessage) // Using the local state variable here
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            HStack {
                TextField("Type a message...", text: $messageToSend)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    guard !messageToSend.isEmpty else { return }
                    if let rawBytes = messageToSend.data(using: .utf8) {
                        networkManager.broadcast(payload: rawBytes)
                        messageToSend = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // ── Push-to-Talk Button ──
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
                                if !audioPipeline.isTransmitting {
                                    audioPipeline.startTransmitting()
                                }
                            }
                            .onEnded { _ in
                                audioPipeline.stopTransmitting()
                            }
                    )
            }
            
            Spacer()
            

            Button("Start Scanning for Peers") {
                networkManager.startMesh()
            }
            .buttonStyle(.bordered)
            .padding(.bottom)
        }
        .padding(.top)

        .onAppear {
            networkManager.onPayloadReceived = { payloadData, senderName in
                if let decodedText = String(data: payloadData, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.receivedMessage = "[\(senderName)]: \(decodedText)"
                    }
                }
            }
        }
    }
}
