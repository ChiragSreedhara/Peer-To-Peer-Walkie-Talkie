import SwiftUI
import Combine
import AVFoundation

struct MeshMessage: Identifiable {
    let id = UUID()
    let sender: String
    let text: String?
    let audioData: Data?
    let timestamp = Date()
}

private extension Color {
    static let wtBackground   = Color(red: 0.039, green: 0.039, blue: 0.059)
    static let wtSurface      = Color(red: 0.075, green: 0.071, blue: 0.110)
    static let wtBorder       = Color(red: 0.14,  green: 0.12,  blue: 0.22)
    static let wtPurple       = Color(red: 0.482, green: 0.184, blue: 0.969)
    static let wtBlue         = Color(red: 0.102, green: 0.451, blue: 0.910)
    static let wtGreen        = Color(red: 0.098, green: 0.863, blue: 0.510)
    static let wtDimText      = Color.white.opacity(0.35)
    static let wtFaintText    = Color.white.opacity(0.18)
}

private let wtGradient = LinearGradient(
    colors: [.wtPurple, .wtBlue],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct ContentView: View {

    @StateObject private var networkManager = MeshRoutingEngine()
    @StateObject private var audioPipeline  = AudioPipelineEngine()

    @State private var isPoweredOn: Bool      = false
    @State private var userName: String       = ContentView.generateRandomCallsign()
    @State private var isEditingName: Bool    = false
    @State private var editNameTemp: String   = ""

    @State private var hasMicPermission       = false
    @State private var showingPermissionAlert = false
    @State private var showDebugLogs          = false

    @State private var inboxMessages: [MeshMessage] = []
    @State private var messageToSend: String = ""
    @State private var selectedTarget: String = "Everyone"
    
    @State private var playingMessageID: UUID? = nil
    
    @State private var peersToIgnore: String = ""

    static func generateRandomCallsign() -> String {
        let nouns = ["Falcon", "Wolf", "Hawk", "Bear", "Fox", "Raven", "Snake", "Echo"]
        let randomNum = Int.random(in: 1...9)
        return "\(nouns.randomElement()!)\(randomNum)"
    }

    var body: some View {
        ZStack {
            Color.wtBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        connectionStatusBadge
                        
                        if isPoweredOn {
                            dmSection
                            inboxSection
                        }

                        Spacer(minLength: 32)

                        pttSection

                        Spacer(minLength: 24)

                        debugSection

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            requestMicPermission()
            wireAudioPipeline()
        }
        .onChange(of: audioPipeline.isPlaying) { isPlaying in
            if !isPlaying {
                playingMessageID = nil
            }
        }
        .alert("Microphone Access Needed", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow microphone access in Settings to use Push to Talk.")
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isPoweredOn.toggle()
                        if isPoweredOn {
                            networkManager.startMesh(withName: userName, ignoring: peersToIgnore)
                        } else {
                            networkManager.stopMesh()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isPoweredOn ? Color.wtGreen.opacity(0.18) : Color.red.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "power")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isPoweredOn ? .wtGreen : .red)
                    }
                }

                if !isPoweredOn {
                    Text("Offline")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                }
            }

            Spacer()

            if isEditingName {
                HStack(spacing: 6) {
                    TextField("Your name", text: $editNameTemp)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(minWidth: 80)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.wtSurface)
                        .clipShape(Capsule())

                    Button {
                        let trimmed = editNameTemp.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { userName = trimmed }
                        isEditingName = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(wtGradient)
                    }
                }
            } else {
                Button {
                    guard !isPoweredOn else { return }
                    editNameTemp = userName
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isPoweredOn ? Color.wtGreen : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(userName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.wtSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.wtBorder, lineWidth: 1))
                }
            }
        }
    }

    private var connectionStatusBadge: some View {
        HStack(spacing: 8) {
            if !isPoweredOn {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 13))
                    .foregroundColor(.wtDimText)
            } else if !networkManager.connectedPeers.isEmpty {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.wtGreen)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .wtDimText))
                    .scaleEffect(0.75)
            }

            Text(isPoweredOn
                 ? (!networkManager.connectedPeers.isEmpty
                    ? "Connected · \(networkManager.connectedPeers.count) peers"
                    : "Searching for peers…")
                 : "Turn on to connect")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(!networkManager.connectedPeers.isEmpty ? .wtGreen : .wtDimText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(!networkManager.connectedPeers.isEmpty ? Color.wtGreen.opacity(0.10) : Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(!networkManager.connectedPeers.isEmpty ? Color.wtGreen.opacity(0.30) : Color.white.opacity(0.08), lineWidth: 1))
    }

    private var dmSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Target:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.wtPurple)
                
                Picker("Target", selection: $selectedTarget) {
                    Text("Everyone").tag("Everyone")
                    ForEach(networkManager.connectedPeers, id: \.self) { peer in
                        Text(peer).tag(peer)
                    }
                }
                .tint(.white)
                Spacer()
            }
            .padding(.horizontal, 8)

            HStack {
                TextField("Type a text message...", text: $messageToSend)
                    .padding(12)
                    .background(Color.wtSurface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.wtBorder, lineWidth: 1))
                    .foregroundColor(.white)
                
                Button {
                    guard !messageToSend.isEmpty, isPoweredOn else { return }
                    if let rawBytes = messageToSend.data(using: .utf8) {
                        let target: String? = selectedTarget == "Everyone" ? nil : selectedTarget
                        networkManager.broadcast(payload: rawBytes, to: target)
                        
                        messageToSend = ""
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(12)
                        .background(wtGradient)
                        .cornerRadius(12)
                }
            }
        }
    }

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chat Inbox")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.wtPurple)
                Spacer()
            }
            .padding(.horizontal, 4)

            if inboxMessages.isEmpty {
                Text("No messages yet...")
                    .font(.system(size: 13))
                    .foregroundColor(.wtDimText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .background(Color.wtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.wtBorder, lineWidth: 1))
            } else {
                VStack(spacing: 10) {
                    ForEach(inboxMessages) { msg in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(msg.sender)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                
                                if let text = msg.text {
                                    Text(text)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.9))
                                } else {
                                    Text(msg.timestamp, style: .time)
                                        .font(.system(size: 11))
                                        .foregroundColor(.wtDimText)
                                }
                            }
                            Spacer()
                            
                            if msg.text != nil {
                                Text(msg.timestamp, style: .time)
                                    .font(.system(size: 11))
                                    .foregroundColor(.wtDimText)
                            } else if let audioData = msg.audioData {
                                let isThisPlaying = (playingMessageID == msg.id) && audioPipeline.isPlaying
                                
                                Button {
                                    playingMessageID = msg.id
                                    audioPipeline.playVoiceNote(audioData)
                                } label: {
                                    Image(systemName: isThisPlaying ? "stop.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(isThisPlaying ? AnyShapeStyle(Color.wtGreen) : AnyShapeStyle(wtGradient))
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.wtSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.wtBorder, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var pttSection: some View {
        VStack(spacing: 12) {
            ZStack {
                if audioPipeline.isTransmitting {
                    ForEach([1, 2, 3], id: \.self) { i in
                        Circle()
                            .stroke(
                                LinearGradient(colors: [Color.wtPurple.opacity(0.35 / Double(i)),
                                                        Color.wtBlue.opacity(0.25 / Double(i))],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                            .frame(width: CGFloat(130 + i * 28), height: CGFloat(130 + i * 28))
                    }
                }

                Circle()
                    .fill(isPoweredOn ? AnyShapeStyle(wtGradient) : AnyShapeStyle(Color.white.opacity(0.07)))
                    .frame(width: 130, height: 130)
                    .shadow(color: audioPipeline.isTransmitting ? Color.wtPurple.opacity(0.55) : (isPoweredOn ? Color.wtBlue.opacity(0.30) : .clear), radius: audioPipeline.isTransmitting ? 30 : 14)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 44))
                            .foregroundColor(isPoweredOn ? .white : .white.opacity(0.20))
                    )
                    .scaleEffect(audioPipeline.isTransmitting ? 1.07 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: audioPipeline.isTransmitting)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard isPoweredOn else { return }
                                guard hasMicPermission else {
                                    showingPermissionAlert = true
                                    return
                                }
                                if !audioPipeline.isTransmitting {
                                    audioPipeline.startTransmitting()
                                }
                            }
                            .onEnded { _ in
                                audioPipeline.stopTransmitting()
                            }
                    )
            }
            .frame(width: 130 + 3 * 28 + 10, height: 130 + 3 * 28 + 10)

            Text(audioPipeline.isTransmitting ? "Recording... (Max 3s)" : (isPoweredOn ? "Push to Talk" : "Turn on to talk"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isPoweredOn ? .wtDimText : .wtFaintText)
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDebugLogs.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                    Text("System / Testing Logs")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(showDebugLogs ? 180 : 0))
                }
                .foregroundColor(.wtFaintText)
            }

            if showDebugLogs {
                VStack(spacing: 8) {
                    TextField("Topology Test: Ignore (e.g. Alice,Bob)", text: $peersToIgnore)
                        .font(.system(size: 12))
                        .padding(8)
                        .background(Color.wtBackground)
                        .cornerRadius(6)
                        .foregroundColor(.white)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(networkManager.debugLogs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color.wtGreen.opacity(0.75))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .frame(height: 140)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.wtBorder, lineWidth: 1))
                }
                .padding(10)
                .background(Color.wtSurface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.wtBorder, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func wireAudioPipeline() {
        audioPipeline.onAudioPacketReady = { data in
            let target: String? = selectedTarget == "Everyone" ? nil : selectedTarget
            networkManager.broadcast(payload: data, to: target)
        }

        networkManager.onPayloadReceived = { payload, senderID, relayer, targetID in
            let senderLabel = senderID == relayer ? senderID : "\(senderID) via \(relayer)"
            
            if let decodedText = String(data: payload, encoding: .utf8) {
                let msg = MeshMessage(sender: senderLabel, text: decodedText, audioData: nil)
                DispatchQueue.main.async { self.inboxMessages.insert(msg, at: 0) }
            } else {
                let msg = MeshMessage(sender: senderLabel, text: nil, audioData: payload)
                DispatchQueue.main.async { self.inboxMessages.insert(msg, at: 0) }
            }
        }
    }

    private func requestMicPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { self.hasMicPermission = granted }
        }
    }
}
