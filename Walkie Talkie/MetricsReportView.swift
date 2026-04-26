import SwiftUI

struct MetricsReportView: View {
    let report: MetricsEngine.Report
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overviewSection
                    audioSection
                    hopSection
                    if !report.perSender.isEmpty { senderSection }
                    textSection
                    dataSection
                    clockNote
                }
                .padding()
            }
            .navigationTitle("Session Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Reset") { onReset(); dismiss() }
                        .foregroundColor(.red)
                }
            }
        }
    }


    private var overviewSection: some View {
        ReportCard(title: "Session Overview") {
            StatRow(label: "Duration", value: report.formattedDuration)
            StatRow(label: "Unique Senders Heard", value: "\(report.perSender.count)")
        }
    }

    private var audioSection: some View {
        ReportCard(title: "Audio Packets") {
            StatRow(label: "Sent (this device)", value: "\(report.audioPacketsSent)")
            StatRow(label: "Received", value: "\(report.audioPacketsReceived)")
            StatRow(label: "Delivery Rate",
                    value: report.audioPacketsReceived == 0 ? "—" :
                        String(format: "%.1f%%", report.deliveryRate * 100))
            StatRow(label: "Packets Lost",
                    value: report.audioPacketsReceived == 0 ? "—" :
                        "\(report.perSender.values.map { $0.packetsExpected - $0.packetsReceived }.reduce(0, +))")
            Divider().padding(.vertical, 2)
            StatRow(label: "Avg Latency",
                    value: report.audioPacketsReceived == 0 ? "—" :
                        String(format: "%.0f ms", report.avgLatencyMs))
            StatRow(label: "Min Latency",
                    value: report.audioPacketsReceived == 0 ? "—" :
                        String(format: "%.0f ms", report.minLatencyMs))
            StatRow(label: "Max Latency",
                    value: report.audioPacketsReceived == 0 ? "—" :
                        String(format: "%.0f ms", report.maxLatencyMs))
            StatRow(label: "Jitter (σ)",
                    value: report.audioPacketsReceived == 0 ? "—" :
                        String(format: "%.0f ms", report.jitterMs))
            Divider().padding(.vertical, 2)
            StatRow(label: "Avg Hop Count",
                    value: report.audioPacketsReceived == 0 ? "—" :
                        String(format: "%.1f", report.avgHopCount))
        }
    }

    private var hopSection: some View {
        ReportCard(title: "Hop Breakdown") {
            if report.hopSenderRows.isEmpty {
                Text("No audio received yet.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                let sortedHops = report.hopDistribution.keys.sorted()
                ForEach(sortedHops, id: \.self) { hop in
                    let hopLabel = hop == 0 ? "Direct" : "\(hop) hop\(hop == 1 ? "" : "s")"
                    let rowsForHop = report.hopSenderRows.filter { $0.hopCount == hop }

                    // Hop group header
                    HStack {
                        Text(hopLabel)
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(hop == 0 ? .green : .orange)
                        Spacer()
                        if let avgLat = report.avgLatencyByHop[hop] {
                            Text(String(format: "avg %.0f ms", avgLat))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, hop == 0 ? 0 : 6)

                    // the rows under this hop group
                    ForEach(rowsForHop) { row in
                        HStack {
                            Text("from \(row.senderID)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding(.leading, 12)
                            Spacer()
                            Text("\(row.packetCount) pkts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            Text(String(format: "%.0f ms", row.avgLatencyMs))
                                .font(.subheadline)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var senderSection: some View {
        ReportCard(title: "Per Sender") {
            HStack {
                Text("Sender").bold().frame(maxWidth: .infinity, alignment: .leading)
                Text("Delivery").bold().frame(width: 65, alignment: .trailing)
                Text("Avg Lat").bold().frame(width: 60, alignment: .trailing)
                Text("Hops").bold().frame(width: 40, alignment: .trailing)
            }
            .font(.caption)
            .foregroundColor(.secondary)

            ForEach(report.perSender.keys.sorted(), id: \.self) { sender in
                if let stats = report.perSender[sender] {
                    HStack {
                        Text(sender)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(String(format: "%.0f%%", stats.deliveryRate * 100))
                            .frame(width: 65, alignment: .trailing)
                            .foregroundColor(stats.deliveryRate > 0.9 ? .green : stats.deliveryRate > 0.7 ? .orange : .red)
                        Text(String(format: "%.0f ms", stats.avgLatencyMs))
                            .frame(width: 60, alignment: .trailing)
                        Text(String(format: "%.1f", stats.avgHopCount))
                            .frame(width: 40, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var textSection: some View {
        ReportCard(title: "Text Messages") {
            StatRow(label: "Received", value: "\(report.textMessagesReceived)")
        }
    }

    private var dataSection: some View {
        ReportCard(title: "Data") {
            let kb = Double(report.totalBytesReceived) / 1024.0
            StatRow(label: "Total Received", value: String(format: "%.1f KB", kb))
        }
    }

    private var clockNote: some View {
        Text("Latency is receive time minus the sender's embedded timestamp")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }
}



private struct ReportCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
        .font(.subheadline)
    }
}
