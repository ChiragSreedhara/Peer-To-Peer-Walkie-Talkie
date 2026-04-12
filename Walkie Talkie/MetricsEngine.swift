import Foundation
import Combine

final class MetricsEngine: ObservableObject {

    // MARK: - Data Types

    struct AudioRecord {
        let senderID: String
        let sequenceNumber: UInt32
        let latencyMs: Double
        let hopCount: Int
        let bytes: Int
    }

    struct TextRecord {
        let senderID: String
        let hopCount: Int
        let bytes: Int
    }

    struct Report {
        let sessionDuration: TimeInterval
        // Audio
        let audioPacketsSent: Int
        let audioPacketsReceived: Int
        let deliveryRate: Double
        let avgLatencyMs: Double
        let minLatencyMs: Double
        let maxLatencyMs: Double
        let jitterMs: Double
        let avgHopCount: Double
        let hopDistribution: [Int: Int]
        let avgLatencyByHop: [Int: Double]
        let hopSenderRows: [HopSenderRow]
        // Text
        let textMessagesReceived: Int
        // General
        let totalBytesReceived: Int
        let perSender: [String: SenderStats]

        struct SenderStats {
            let packetsReceived: Int
            let packetsExpected: Int
            let deliveryRate: Double
            let avgLatencyMs: Double
            let avgHopCount: Double
        }

        struct HopSenderRow: Identifiable {
            var id: String { "\(hopCount)-\(senderID)" }
            let hopCount: Int
            let senderID: String
            let packetCount: Int
            let avgLatencyMs: Double
        }

        var formattedDuration: String {
            let total = Int(sessionDuration)
            let mins = total / 60
            let secs = total % 60
            return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
        }
    }

    // MARK: - State

    @Published private(set) var audioReceived: [AudioRecord] = []
    @Published private(set) var textReceived: [TextRecord] = []
    @Published private(set) var audioSentCount: Int = 0

    private let sessionStart = Date()

    // MARK: - Recording

    func recordAudioSent() {
        DispatchQueue.main.async { self.audioSentCount += 1 }
    }

    func recordAudioReceived(packet: AudioPacket, hopCount: Int, bytes: Int) {
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let latencyMs = max(0.0, Double(nowMs) - Double(packet.timestamp))
        let record = AudioRecord(
            senderID: packet.senderID,
            sequenceNumber: packet.sequenceNumber,
            latencyMs: latencyMs,
            hopCount: hopCount,
            bytes: bytes
        )
        DispatchQueue.main.async { self.audioReceived.append(record) }
    }

    func recordTextReceived(senderID: String, hopCount: Int, bytes: Int) {
        let record = TextRecord(senderID: senderID, hopCount: hopCount, bytes: bytes)
        DispatchQueue.main.async { self.textReceived.append(record) }
    }

    func reset() {
        DispatchQueue.main.async {
            self.audioReceived.removeAll()
            self.textReceived.removeAll()
            self.audioSentCount = 0
        }
    }

    // MARK: - Report Generation

    func generateReport() -> Report {
        let duration = Date().timeIntervalSince(sessionStart)
        let latencies = audioReceived.map(\.latencyMs)

        let avgLatency = latencies.isEmpty ? 0.0 : latencies.reduce(0, +) / Double(latencies.count)
        let minLatency = latencies.min() ?? 0.0
        let maxLatency = latencies.max() ?? 0.0

        let jitter: Double = {
            guard latencies.count > 1 else { return 0.0 }
            let variance = latencies.map { pow($0 - avgLatency, 2) }.reduce(0, +) / Double(latencies.count)
            return sqrt(variance)
        }()

        var hopDist: [Int: Int] = [:]
        var hopLatBuckets: [Int: [Double]] = [:]
        for r in audioReceived {
            hopDist[r.hopCount, default: 0] += 1
            hopLatBuckets[r.hopCount, default: []].append(r.latencyMs)
        }
        let avgLatByHop = hopLatBuckets.mapValues { $0.reduce(0, +) / Double($0.count) }

        var hopSenderBuckets: [Int: [String: [Double]]] = [:]
        for r in audioReceived {
            hopSenderBuckets[r.hopCount, default: [:]][r.senderID, default: []].append(r.latencyMs)
        }
        var hopSenderRows: [Report.HopSenderRow] = []
        for (hop, senders) in hopSenderBuckets {
            for (sender, lats) in senders {
                hopSenderRows.append(Report.HopSenderRow(
                    hopCount: hop,
                    senderID: sender,
                    packetCount: lats.count,
                    avgLatencyMs: lats.reduce(0, +) / Double(lats.count)
                ))
            }
        }
        hopSenderRows.sort { $0.hopCount == $1.hopCount ? $0.senderID < $1.senderID : $0.hopCount < $1.hopCount }

        let avgHopCount = audioReceived.isEmpty ? 0.0 :
            Double(audioReceived.map(\.hopCount).reduce(0, +)) / Double(audioReceived.count)

        let senderIDs = Set(audioReceived.map(\.senderID))
        var perSender: [String: Report.SenderStats] = [:]
        var totalExpected = 0
        var totalReceived = 0
        for id in senderIDs {
            let recs = audioReceived.filter { $0.senderID == id }
            let lats = recs.map(\.latencyMs)
            let seqs = recs.map(\.sequenceNumber)
            let expected: Int
            if let minSeq = seqs.min(), let maxSeq = seqs.max() {
                expected = Int(maxSeq - minSeq) + 1
            } else {
                expected = recs.count
            }
            totalExpected += expected
            totalReceived += recs.count
            perSender[id] = Report.SenderStats(
                packetsReceived: recs.count,
                packetsExpected: expected,
                deliveryRate: expected > 0 ? min(1.0, Double(recs.count) / Double(expected)) : 0.0,
                avgLatencyMs: lats.isEmpty ? 0 : lats.reduce(0, +) / Double(lats.count),
                avgHopCount: Double(recs.map(\.hopCount).reduce(0, +)) / Double(recs.count)
            )
        }
        let deliveryRate = totalExpected > 0 ? min(1.0, Double(totalReceived) / Double(totalExpected)) : 0.0

        let totalBytes = audioReceived.map(\.bytes).reduce(0, +) + textReceived.map(\.bytes).reduce(0, +)

        return Report(
            sessionDuration: duration,
            audioPacketsSent: audioSentCount,
            audioPacketsReceived: audioReceived.count,
            deliveryRate: deliveryRate,
            avgLatencyMs: avgLatency,
            minLatencyMs: minLatency,
            maxLatencyMs: maxLatency,
            jitterMs: jitter,
            avgHopCount: avgHopCount,
            hopDistribution: hopDist,
            avgLatencyByHop: avgLatByHop,
            hopSenderRows: hopSenderRows,
            textMessagesReceived: textReceived.count,
            totalBytesReceived: totalBytes,
            perSender: perSender
        )
    }
}
