import Foundation
import UIKit
import Combine
import MultipeerConnectivity

struct MeshPacket: Codable {
    let messageID: UUID
    let senderID: String
    let targetID: String?
    var ttl: Int
    let payload: Data
}

class MeshRoutingEngine: ObservableObject {
    private let transport = MultipeerManager()
    private var seenMessageIDs: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()
    private var myName: String = ""
    private let meshTTL = 3
    
    @Published var connectedPeers: [String] = []
    @Published var debugLogs: [String] = []
    
    var onPayloadReceived: ((Data, String, String, String?, Int) -> Void)?
    
    init() {
        setupTransportInteractions()
    }
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.debugLogs.insert(message, at: 0)
        }
    }
    
    func startMesh(withName name: String, ignoring: String = "") {
        self.myName = name
        let ignoreArray = ignoring.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        
        transport.startNetworking(as: name, ignoring: ignoreArray)
    }

    func stopMesh() {
        transport.stopNetworking()
        seenMessageIDs.removeAll()
    }

    func clearMesh() {
        seenMessageIDs.removeAll()
        DispatchQueue.main.async {
            self.debugLogs.removeAll()
        }
        transport.restartScanning()
    }
    
    func stopMesh() {
            transport.stopNetworking()
        }
    
    private func setupTransportInteractions() {
        transport.onDebugLog = { [weak self] message in
            self?.log(message)
        }
        
        transport.onPacketReceived = { [weak self] rawBytes, immediateSenderName in
            self?.processIncomingBytes(rawBytes, from: immediateSenderName)
        }
        
        transport.$connectedPeers
            .receive(on: RunLoop.main)
            .map { peers in
                peers.map { $0.displayName }
            }
            .assign(to: \.connectedPeers, on: self)
            .store(in: &cancellables)
    }
    
    private func processIncomingBytes(_ data: Data, from immediateSender: String) {
            guard let packet = try? JSONDecoder().decode(MeshPacket.self, from: data) else {
                log("Layer 3: issues with mesh packet")
                return
            }
            
            guard !seenMessageIDs.contains(packet.messageID) else { return }
            registerMessageSeen(packet.messageID)
            
            let shortID = packet.messageID.uuidString.prefix(4)
            log("Layer 3: Caught packet [\(shortID)] originally from \(packet.senderID). TTL: \(packet.ttl)")
            
            let hopCount = meshTTL - packet.ttl
            if packet.targetID == nil || packet.targetID == self.myName {
                onPayloadReceived?(packet.payload, packet.senderID, immediateSender, packet.targetID, hopCount)
            } else {
                log("Layer 3: Packet meant for \(packet.targetID!). Passing on and skipping unpacking")
            }
            
            var forwardedPacket = packet
            forwardedPacket.ttl -= 1
            
            if forwardedPacket.ttl > 0 {
                forwardToMesh(packet: forwardedPacket, excluding: immediateSender)
            } else {
                log("Layer 3: Packet [\(shortID)] reached its TTL limit. Dropping pckt.")
            }
        }
            
        func broadcast(payload: Data, to target: String?) {
            let newPacket = MeshPacket(
                messageID: UUID(),
                senderID: self.myName,
                targetID: target,
                ttl: meshTTL,
                payload: payload
            )
            
            registerMessageSeen(newPacket.messageID)
            guard let rawData = try? JSONEncoder().encode(newPacket) else { return }
            
            log("Layer 3: Starting new blast [\(newPacket.messageID.uuidString.prefix(4))] to \(target ?? "everyone")")
            transport.broadcastToNeighbors(data: rawData)
        }
        
        private func forwardToMesh(packet: MeshPacket, excluding: String) {
            guard let rawData = try? JSONEncoder().encode(packet) else { return }
            log(" Forwarding [\(packet.messageID.uuidString.prefix(4))], new TTL: \(packet.ttl) (skipping \(excluding))")
            transport.broadcastToNeighbors(data: rawData, excluding: excluding)
        }
    
    private func registerMessageSeen(_ id: UUID) {
        seenMessageIDs.insert(id)
        if seenMessageIDs.count > 1000 {
            seenMessageIDs.removeAll()
            seenMessageIDs.insert(id)
        }
    }
}
