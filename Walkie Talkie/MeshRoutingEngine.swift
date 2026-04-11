import Foundation
import UIKit
import Combine
import MultipeerConnectivity

enum MeshPayloadType: String, Codable {
    case text
    case voiceNote
    case liveAudio
}

struct MeshPacket: Codable {
    let messageID: UUID
    let senderID: String
    let targetID: String?
    var ttl: Int
    let payload: Data
    let payloadType: MeshPayloadType
}

class MeshRoutingEngine: ObservableObject {
    private let transport = MultipeerManager()
    private var seenMessageIDs: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()
    private var myName: String = ""
    
    @Published var connectedPeers: [String] = []
    @Published var debugLogs: [String] = []
    
    var onPayloadReceived: ((Data, String, String, String?, MeshPayloadType) -> Void)?
    
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
        
        log("Layer 3: Booting up Mesh Node as '\(name)'...")
        transport.startNetworking(as: name, ignoring: ignoreArray)
    }
    
    func stopMesh() {
            transport.stopNetworking()
            log("Layer 3: Radios powered down.")
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
                log("Layer 3 Error: Failed to parse MeshPacket wrapper.")
                return
            }
            
            guard !seenMessageIDs.contains(packet.messageID) else { return }
            registerMessageSeen(packet.messageID)
            
            let shortID = packet.messageID.uuidString.prefix(4)
            log("Layer 3: Caught packet [\(shortID)] originally from \(packet.senderID). TTL: \(packet.ttl)")
            
            if packet.targetID == nil || packet.targetID == self.myName {
                onPayloadReceived?(packet.payload, packet.senderID, immediateSender, packet.targetID, packet.payloadType)
            } else {
                log("Layer 3: Packet targeted for \(packet.targetID!). I am just a middle-man. Skipping UI.")
            }
            
            var forwardedPacket = packet
            forwardedPacket.ttl -= 1
            
            if forwardedPacket.ttl > 0 {
                forwardToMesh(packet: forwardedPacket, excluding: immediateSender)
            } else {
                log("Layer 3: Packet [\(shortID)] reached TTL limit. Dropping.")
            }
        }
            
        func broadcast(payload: Data, to target: String?, type: MeshPayloadType) {
            let newPacket = MeshPacket(
                messageID: UUID(),
                senderID: self.myName,
                targetID: target,
                ttl: 3,
                payload: payload,
                payloadType: type
            )
            
            registerMessageSeen(newPacket.messageID)
            guard let rawData = try? JSONEncoder().encode(newPacket) else { return }
            
            log("Layer 3: Originating new blast [\(newPacket.messageID.uuidString.prefix(4))] to \(target ?? "Everyone")")
            transport.broadcastToNeighbors(data: rawData)
        }
        
        func broadcastLiveAudio(payload: Data, to target: String?) {
            let newPacket = MeshPacket(
                messageID: UUID(),
                senderID: self.myName,
                targetID: target,
                ttl: 5,
                payload: payload,
                payloadType: .liveAudio
            )
            registerMessageSeen(newPacket.messageID)
            guard let rawData = try? JSONEncoder().encode(newPacket) else { return }
            transport.broadcastUnreliableToNeighbors(data: rawData)
        }
        
        private func forwardToMesh(packet: MeshPacket, excluding: String) {
            guard let rawData = try? JSONEncoder().encode(packet) else { return }
            log("Layer 3: Forwarding [\(packet.messageID.uuidString.prefix(4))] -> TTL: \(packet.ttl) (Skipping \(excluding))")
            if packet.payloadType == .liveAudio {
                transport.broadcastUnreliableToNeighbors(data: rawData, excluding: excluding)
            } else {
                transport.broadcastToNeighbors(data: rawData, excluding: excluding)
            }
        }
    
    private func registerMessageSeen(_ id: UUID) {
        seenMessageIDs.insert(id)
        if seenMessageIDs.count > 1000 {
            seenMessageIDs.removeAll()
            seenMessageIDs.insert(id)
        }
    }
}
