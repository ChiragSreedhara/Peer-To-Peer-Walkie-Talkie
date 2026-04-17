import Foundation

struct AudioPacket: Codable {
    let sequenceNumber: UInt32
    let timestamp: UInt64
    let frameDurationMs: UInt16
    let senderID: String
    let totalSent: UInt32

    let opusFrames: [Data]
    
    func serialize() -> Data? {
        return try? JSONEncoder().encode(self)
    }
    
    static func deserialize(from data: Data) -> AudioPacket? {
        return try? JSONDecoder().decode(AudioPacket.self, from: data)
    }
}
