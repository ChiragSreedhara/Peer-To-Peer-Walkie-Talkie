import SwiftUI
import MultipeerConnectivity
import Combine


struct ContentView: View {
    @StateObject var networkManager = MeshRoutingEngine()
    
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
