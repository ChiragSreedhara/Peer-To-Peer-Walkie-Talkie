import Foundation
import AVFoundation
import Combine

final class SyncAudioEngine: ObservableObject {
    
    @Published private(set) var isTransmitting = false
    @Published private(set) var isPlaying = false
    
    var onAudioPacketReady: ((Data) -> Void)?
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    
    private let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent("voicenote.m4a")
    
    private var leftoverSamples: [Float] = []
    private let audioQueue = DispatchQueue(label: "com.walkietalkie.audio", qos: .userInteractive)
    
    private var sequenceCounter: UInt32 = 0
    func resetSequenceCounter() { sequenceCounter = 0 }
    private var playbackTimer: DispatchSourceTimer?
    private let playbackQueue = DispatchQueue(label: "com.walkietalkie.playback", qos: .userInteractive)
    
    private var batchedFrames: [Data] = []
    private let framesPerBatch = 25
    private var emptyDrainCount = 0
    private let emptyDrainThreshold = 25
    
    init() {
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }
    
    // MARK: - Sending
    func startTransmitting() {
        guard !isTransmitting else { return }
        
        let inputNode = captureEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard let targetFormat = AudioConstants.pcmFormat as AVAudioFormat?,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }
        
        leftoverSamples.removeAll()
        batchedFrames.removeAll()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, _) in
            guard let self = self else { return }
            
            let ratio = AudioConstants.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 400
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            
            var error: NSError?
            var hasData = true
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if hasData {
                    outStatus.pointee = .haveData
                    hasData = false
                    return buffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }
            
            guard status != .error, error == nil else { return }
            
            let channelData = convertedBuffer.floatChannelData![0]
            let newSamples = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))
            
            self.audioQueue.async {
                self.leftoverSamples.append(contentsOf: newSamples)
                let frameSamples = Int(AudioConstants.frameSamples)
                
                while self.leftoverSamples.count >= frameSamples {
                    let chunkSamples = Array(self.leftoverSamples.prefix(frameSamples))
                    self.leftoverSamples.removeFirst(frameSamples)
                    
                    guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(frameSamples)) else { continue }
                    chunkBuffer.frameLength = AVAudioFrameCount(frameSamples)
                    chunkBuffer.floatChannelData![0].assign(from: chunkSamples, count: frameSamples)
                    
                    if let compressedData = self.codec.encode(pcmBuffer: chunkBuffer) {
                        self.batchedFrames.append(compressedData)
                        
                        if self.batchedFrames.count >= self.framesPerBatch {
                            self.sequenceCounter += 1
                            let packet = AudioPacket(
                                sequenceNumber: self.sequenceCounter - 1,
                                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                                frameDurationMs: AudioConstants.frameDurationMs,
                                senderID: UIDevice.current.name,
                                totalSent: self.sequenceCounter,
                                opusFrames: self.batchedFrames
                            )
                            self.batchedFrames.removeAll()
                            
                            let serializedData = packet.serialize()
                            DispatchQueue.global(qos: .userInitiated).async {
                                if let data = serializedData {
                                    self.onAudioPacketReady?(data)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordURL, settings: settings)
            audioRecorder?.delegate = self
            
            audioRecorder?.record(forDuration: 3.0)
            
            DispatchQueue.main.async { self.isTransmitting = true }
            audioPlayer?.stop()
            DispatchQueue.main.async { self.isPlaying = false }
        } catch {
            print("error: \(error)")
        }
    }
    
    func stopTransmitting() {
        guard isTransmitting else { return }
        captureEngine.inputNode.removeTap(onBus: 0)
        captureEngine.stop()
        
        if !batchedFrames.isEmpty {
            sequenceCounter += 1
            let packet = AudioPacket(
                sequenceNumber: sequenceCounter - 1,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                frameDurationMs: AudioConstants.frameDurationMs,
                senderID: UIDevice.current.name,
                totalSent: sequenceCounter,
                opusFrames: batchedFrames
            )
            if let serialized = packet.serialize() {
                onAudioPacketReady?(serialized)
            }
            batchedFrames.removeAll()
        }
        
        DispatchQueue.main.async { self.isTransmitting = false }
        
        guard flag, let data = try? Data(contentsOf: recordURL) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.onAudioPacketReady?(data)
        }
    }
    
    func playVoiceNote(_ data: Data) {
        if isPlaying {
            audioPlayer?.stop()
        }
        
        do {
            try playbackEngine.start()
            playerNode.play()
        } catch { print("error:  \(error)") }
    }
    
    private func startPlaybackTimerIfNeeded() {
        guard playbackTimer == nil else { return }
        emptyDrainCount = 0
        DispatchQueue.main.async { self.isReceiving = true }
        
        if !playbackEngine.isRunning {
            try? playbackEngine.start()
            playerNode.play()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.cancel()
        playbackTimer = nil
        DispatchQueue.main.async { self.isReceiving = false }
    }
     
    private func drainBuffersAndPlay() {
        var anyActive = false
        for (_, buffer) in jitterBuffers {
            guard let frameData = buffer.dequeueFrame() else { continue }
            anyActive = true

            guard let pcmBuffer = codec.decode(compressedData: frameData) else { continue }
            playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }

        if anyActive {
            emptyDrainCount = 0
        } else {
            emptyDrainCount += 1
            if emptyDrainCount >= emptyDrainThreshold { stopPlaybackTimer() }
        }
    }
    
    private func jitterBufferFor(sender: String) -> JitterBuffer {
        if let existing = jitterBuffers[sender] { return existing }
        let newBuffer = JitterBuffer(maxDepth: 10)
        jitterBuffers[sender] = newBuffer
        return newBuffer
    }
}
