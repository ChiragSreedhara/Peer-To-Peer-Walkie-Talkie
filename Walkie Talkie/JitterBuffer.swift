//
//  JitterBuffer.swift
//  Walkie Talkie
//
//  Created by Nicole Li on 4/5/26.
//
//  Audio Processing Layer - Jitter Buffer
//
//  Because packets travel through a multi-hop mesh using MPC's `.unreliable`
//  mode (UDP-like), they can arrive out of order, in bursts, or not at all.
//
//  This buffer collects incoming AudioPackets, sorts them by sequence number,
//  and releases them in-order to the audio player at a steady cadence.
//
//  Design choices:
//    • Fixed-depth buffer (configurable, default 5 frames = 100 ms at 20 ms/frame).
//    • If a gap persists past the buffer depth, the missing frame is skipped
//      (Opus PLC or silence insertion handles it downstream).
//    • Late packets that arrive after their slot has been played are dropped.
//

import Foundation

final class JitterBuffer {
    
    /// Maximum number of frames the buffer will hold before forcing playback.
    private let maxDepth: Int
    
    /// The next sequence number the consumer expects to play.
    private var nextPlaybackSeq: UInt32? = nil
    
    /// Packets waiting to be played, keyed by sequence number.
    private var pending: [UInt32: AudioPacket] = [:]
    
    /// Serial queue protecting the buffer state.
    private let queue = DispatchQueue(label: "com.walkietalkie.jitterbuffer")
    
    /// Stats for debugging.
    private(set) var droppedLateCount: Int = 0
    private(set) var skippedGapCount: Int = 0
    
    init(maxDepth: Int = 5) {
        self.maxDepth = maxDepth
    }
    
    /// Insert an incoming packet into the buffer.
    func insert(_ packet: AudioPacket) {
        queue.sync {
            // If we haven't started yet, anchor on this packet.
            if nextPlaybackSeq == nil {
                nextPlaybackSeq = packet.sequenceNumber
            }
            
            // Drop packets that are older than what we're currently playing.
            if let next = nextPlaybackSeq, packet.sequenceNumber < next {
                droppedLateCount += 1
                return
            }
            
            pending[packet.sequenceNumber] = packet
        }
    }
    
    /// Pull the next in-order packet for playback.
    ///
    /// Returns `nil` if the buffer hasn't accumulated enough depth yet
    /// (i.e., we're still in the initial fill phase) OR if the buffer is empty.
    func dequeue() -> AudioPacket? {
        return queue.sync {
            guard let nextSeq = nextPlaybackSeq else { return nil }
            
            // If the next expected packet is present, return it.
            if let packet = pending.removeValue(forKey: nextSeq) {
                nextPlaybackSeq = nextSeq + 1
                return packet
            }
            
            // The expected packet is missing. Check if we've buffered enough
            // future packets that we should skip the gap.
            let bufferedAhead = pending.keys.filter { $0 > nextSeq }.count
            if bufferedAhead >= maxDepth {
                // Jump to the lowest available sequence number.
                let lowestAvailable = pending.keys.filter { $0 > nextSeq }.min()!
                let gap = Int(lowestAvailable - nextSeq)
                skippedGapCount += gap
                
                nextPlaybackSeq = lowestAvailable + 1
                return pending.removeValue(forKey: lowestAvailable)
            }
            
            // Not enough data yet; tell the caller to wait / insert silence.
            return nil
        }
    }
    
    /// Check whether the buffer has enough frames to begin playback.
    /// Call this before starting the playback timer.
    var isReady: Bool {
        return queue.sync {
            pending.count >= maxDepth / 2  // start once half-full
        }
    }
    
    /// Flush all state (e.g., when the sender stops transmitting).
    func reset() {
        queue.sync {
            pending.removeAll()
            nextPlaybackSeq = nil
        }
    }
}
