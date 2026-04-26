import Foundation

struct AsyncAudioPacket: Codable {
    let timestamp: UInt64
    let senderID: String
    let totalSent: UInt32
    let audioData: Data

    func serialize() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    static func deserialize(from data: Data) -> AsyncAudioPacket? {
        return try? JSONDecoder().decode(AsyncAudioPacket.self, from: data)
    }
}
