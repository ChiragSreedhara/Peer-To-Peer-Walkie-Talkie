import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @StateObject var networkManager = MultipeerManager()
    
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
                
                // Loop through the array and list everyone's name!
                ForEach(networkManager.connectedPeers, id: \.self) { peer in
                    Text("📱 \(peer.displayName)")
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
                        networkManager.broadcastToNeighbors(data: rawBytes)
                        messageToSend = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button("Start Scanning for Peers") {
                networkManager.startNetworking()
            }
            .buttonStyle(.bordered)
            .padding(.bottom)
        }
        .padding(.top)

        //delete this section once layer 3 is done
        .onAppear {
            networkManager.onPacketReceived = { rawData in
                if let decodedText = String(data: rawData, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.receivedMessage = decodedText
                    }
                }
            }
        }
    }
}
