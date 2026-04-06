//
//  AudioPacket.swift
//  Walkie Talkie
//
//  Created by Nicole Li on 4/5/26.
//
//  Audio Processing Layer - Packet Structure
//
//  This wraps raw Opus-encoded audio frames in a structure containing
//  sequence numbers so the receiver can reorder out-of-order packets
//  and feed them smoothly to the speaker.
//

import Foundation

struct AudioPacket: Codable {
    /// Monotonically increasing sequence number for reordering at the receiver.
    let sequenceNumber: UInt32
    
    /// Timestamp in milliseconds (sender's clock) — used by the jitter buffer
    /// to pace playback and detect gaps.
    let timestamp: UInt64
    
    /// Duration of this audio frame in milliseconds (typically 20 ms for Opus).
    let frameDurationMs: UInt16
    
    /// The sender's peer ID so the receiver can maintain per-sender jitter buffers.
    let senderID: String
    
    /// The raw Opus-encoded audio bytes.
    let opusData: Data
    
    /// Convenience: serialize to Data for hand-off to the mesh routing engine.
    func serialize() -> Data? {
        return try? JSONEncoder().encode(self)
    }
    
    /// Convenience: deserialize from Data received from the mesh routing engine.
    static func deserialize(from data: Data) -> AudioPacket? {
        return try? JSONDecoder().decode(AudioPacket.self, from: data)
    }
}
