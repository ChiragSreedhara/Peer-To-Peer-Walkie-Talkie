//
//  ContentView.swift
//  Walkie Talkie
//
//  Created by Chirag Sreedhara on 4/3/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject var networkManager = MultipeerManager()
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Layer 4 Test UI")
                .font(.headline)
            
            Text("Status: \(networkManager.connectionStatus)")
                .foregroundColor(.blue)
            
            Text("Received: \(networkManager.receivedMessage)")
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            
            Button("Start Scanning") {
                networkManager.startNetworking()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Send Hello World Blast") {
                if let dumbBytes = "Hello from \(UIDevice.current.name)!".data(using: .utf8) {
                    networkManager.broadcastToNeighbors(data: dumbBytes)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
