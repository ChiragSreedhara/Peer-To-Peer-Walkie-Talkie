//
//  MeshRoutingEngine.swift
//  Walkie Talkie
//
//  Created by Aryamann Sheoran on 4/5/26.
//


import Foundation
import UIKit
import Combine
import MultipeerConnectivity

struct MeshPacket: Codable {
    let messageID: UUID
    let senderID: String
    var ttl: Int
    let payload: Data
}

class MeshRoutingEngine: ObservableObject {
    
    private let transport = MultipeerManager()
    private var seenMessageIDs: Set<UUID> = []
    
    private var cancellables = Set<AnyCancellable>()
    
    @Published var connectedPeers: [String] = []
    
    var onPayloadReceived: ((Data, String) -> Void)?
    
    init() {
        setupTransportInteractions()
    }
    
    func startMesh() {
        transport.startNetworking()
    }
    
    
    private func setupTransportInteractions() {
        transport.onPacketReceived = { [weak self] rawBytes in
            self?.processIncomingBytes(rawBytes)
        }
        
        transport.$connectedPeers
            .receive(on: RunLoop.main)
            .map { peers in
                peers.map { $0.displayName }
            }
            .assign(to: \.connectedPeers, on: self)
            .store(in: &cancellables)
    }
    
    private func processIncomingBytes(_ data: Data) {
        guard let packet = try? JSONDecoder().decode(MeshPacket.self, from: data) else {
            print("Layer 3 Error: Failed to parse MeshPacket wrapper.")
            return
        }
        
        guard !seenMessageIDs.contains(packet.messageID) else {
            return
        }
        
        registerMessageSeen(packet.messageID)
        print("Layer 3: Caught new packet \(packet.messageID.uuidString.prefix(4)) from \(packet.senderID). TTL: \(packet.ttl)")
        
        onPayloadReceived?(packet.payload, packet.senderID)
        
        var forwardedPacket = packet
        forwardedPacket.ttl -= 1
        
        if forwardedPacket.ttl > 0 {
            forwardToMesh(packet: forwardedPacket)
        } else {
            print("Layer 3: Packet \(packet.messageID.uuidString.prefix(4)) reached TTL limit. Dropping.")
        }
    }
        
    func broadcast(payload: Data) {
        let newPacket = MeshPacket(
            messageID: UUID(),
            senderID: UIDevice.current.name,
            ttl: 3,
            payload: payload
        )
        
        registerMessageSeen(newPacket.messageID)
        
        guard let rawData = try? JSONEncoder().encode(newPacket) else {
            print("Layer 3 Error: Failed to encode outgoing packet.")
            return
        }
        
        print("Layer 3: Originating new blast for packet \(newPacket.messageID.uuidString.prefix(4))")
        transport.broadcastToNeighbors(data: rawData)
    }
    
    private func forwardToMesh(packet: MeshPacket) {
        guard let rawData = try? JSONEncoder().encode(packet) else { return }
        print("Layer 3: Forwarding packet \(packet.messageID.uuidString.prefix(4)) -> New TTL: \(packet.ttl)")
        transport.broadcastToNeighbors(data: rawData)
    }
    
    private func registerMessageSeen(_ id: UUID) {
        seenMessageIDs.insert(id)
        if seenMessageIDs.count > 1000 {
            seenMessageIDs.removeAll()
            seenMessageIDs.insert(id)
        }
    }
    
}
