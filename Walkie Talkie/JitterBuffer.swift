import Foundation

final class JitterBuffer {
    
    private let maxDepth: Int
    private var nextPlaybackSeq: UInt32? = nil
    
    private var pendingPackets: [UInt32: AudioPacket] = [:]
    
    private var activePacket: AudioPacket? = nil
    private var activeFrameIndex: Int = 0
    
    private let queue = DispatchQueue(label: "com.walkietalkie.jitterbuffer")
    
    init(maxDepth: Int = 10) {
        self.maxDepth = maxDepth
    }
    
    func insert(_ packet: AudioPacket) {
        queue.sync {
            if nextPlaybackSeq == nil {
                nextPlaybackSeq = packet.sequenceNumber
            }
            if let next = nextPlaybackSeq, packet.sequenceNumber < next { return }
            pendingPackets[packet.sequenceNumber] = packet
        }
    }
    
    func dequeueFrame() -> Data? {
        return queue.sync {
            guard let expectedSeq = nextPlaybackSeq else { return nil }
            
            if activePacket == nil {
                if let packet = pendingPackets.removeValue(forKey: expectedSeq) {
                    activePacket = packet
                    activeFrameIndex = 0
                    nextPlaybackSeq = expectedSeq + 1
                } else {
                    if pendingPackets.count > maxDepth {
                        let lowestAvailable = pendingPackets.keys.min()!
                        nextPlaybackSeq = lowestAvailable
                        print("JitterBuffer: Healing gap. Jumping to \(lowestAvailable)")
                    }
                    return nil
                }
            }
            
            guard let packet = activePacket else { return nil }
            let frameData = packet.opusFrames[activeFrameIndex]
            
            activeFrameIndex += 1
            
            if activeFrameIndex >= packet.opusFrames.count {
                activePacket = nil
            }
            
            return frameData
        }
    }
    
    func reset() {
        queue.sync {
            pendingPackets.removeAll()
            activePacket = nil
            nextPlaybackSeq = nil
        }
    }
}
