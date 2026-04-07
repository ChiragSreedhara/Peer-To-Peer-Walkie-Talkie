import AVFoundation
import UIKit
import Combine

final class AudioPipelineEngine: ObservableObject {
    
    @Published private(set) var isTransmitting = false
    @Published private(set) var isReceiving = false
    
    var onAudioPacketReady: ((Data) -> Void)?
    
    private let captureEngine = AVAudioEngine()
    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private let codec: AudioCodec = OpusCodecWrapper()
    private var jitterBuffers: [String: JitterBuffer] = [:]
    
    private var leftoverSamples: [Float] = []
    private let audioQueue = DispatchQueue(label: "com.walkietalkie.audio", qos: .userInteractive)
    
    private var sequenceCounter: UInt32 = 0
    private var playbackTimer: DispatchSourceTimer?
    private let playbackQueue = DispatchQueue(label: "com.walkietalkie.playback", qos: .userInteractive)
    
    // NEW: The Batching Tray
    private var batchedFrames: [Data] = []
    private let framesPerBatch = 4
    
    init() {
        configureAudioSession()
        setupPlaybackEngine()
    }
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setPreferredSampleRate(AudioConstants.sampleRate)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
        } catch {
            print("AudioPipeline: Failed to config session — \(error)")
        }
    }
    
    func startTransmitting() {
        guard !isTransmitting else { return }
        
        let inputNode = captureEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard let targetFormat = AudioConstants.pcmFormat as AVAudioFormat?,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }
        
        leftoverSamples.removeAll()
        batchedFrames.removeAll()
        sequenceCounter = 0
        
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
                    
                    // Encode and add to the batching tray
                    if let compressedData = self.codec.encode(pcmBuffer: chunkBuffer) {
                        self.batchedFrames.append(compressedData)
                        
                        // Once the tray is full, send the packet!
                        if self.batchedFrames.count >= self.framesPerBatch {
                            let packet = AudioPacket(
                                sequenceNumber: self.sequenceCounter,
                                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                                frameDurationMs: AudioConstants.frameDurationMs,
                                senderID: UIDevice.current.name,
                                opusFrames: self.batchedFrames // Send the whole batch
                            )
                            self.sequenceCounter += 1
                            self.batchedFrames.removeAll() // Empty the tray
                            
                            if let serialized = packet.serialize() {
                                self.onAudioPacketReady?(serialized)
                            }
                        }
                    }
                }
            }
        }
        
        do {
            try captureEngine.start()
            DispatchQueue.main.async { self.isTransmitting = true }
        } catch {
            print("AudioPipeline: Failed to start capture — \(error)")
        }
    }
    
    func stopTransmitting() {
        guard isTransmitting else { return }
        captureEngine.inputNode.removeTap(onBus: 0)
        captureEngine.stop()
        
        // Flush any remaining frames in the tray before shutting off
        if !batchedFrames.isEmpty {
            let packet = AudioPacket(
                sequenceNumber: sequenceCounter,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                frameDurationMs: AudioConstants.frameDurationMs,
                senderID: UIDevice.current.name,
                opusFrames: batchedFrames
            )
            if let serialized = packet.serialize() {
                onAudioPacketReady?(serialized)
            }
            batchedFrames.removeAll()
        }
        
        DispatchQueue.main.async { self.isTransmitting = false }
    }
    
    func receiveAudioData(_ data: Data, from senderName: String) {
        guard let packet = AudioPacket.deserialize(from: data) else { return }
        let buffer = jitterBufferFor(sender: senderName)
        buffer.insert(packet)
        startPlaybackTimerIfNeeded()
    }
    
    private func setupPlaybackEngine() {
        playbackEngine.attach(playerNode)
        let format = AudioConstants.pcmFormat
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: format)
        do {
            try playbackEngine.start()
            playerNode.play()
        } catch { print("AudioPipeline: Playback start failed — \(error)") }
    }
    
    private func startPlaybackTimerIfNeeded() {
        guard playbackTimer == nil else { return }
        DispatchQueue.main.async { self.isReceiving = true }
        
        if !playbackEngine.isRunning {
            try? playbackEngine.start()
            playerNode.play()
        }
        
        let timer = DispatchSource.makeTimerSource(queue: playbackQueue)
        let intervalMs = Int(AudioConstants.frameDurationMs)
        // Wait exactly 120ms before starting playback to build a healthy buffer
        timer.schedule(deadline: .now() + .milliseconds(intervalMs * 6), repeating: .milliseconds(intervalMs))
        
        timer.setEventHandler { [weak self] in
            self?.drainBuffersAndPlay()
        }
        timer.resume()
        playbackTimer = timer
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.cancel()
        playbackTimer = nil
        DispatchQueue.main.async { self.isReceiving = false }
    }
    
    private func drainBuffersAndPlay() {
        var anyActive = false
        for (_, buffer) in jitterBuffers {
            // Because packets now hold multiple frames, the JitterBuffer
            // hands us one FRAME at a time, not one packet at a time!
            guard let frameData = buffer.dequeueFrame() else { continue }
            anyActive = true
            
            guard let pcmBuffer = codec.decode(compressedData: frameData) else { continue }
            playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }
        
        if !anyActive { stopPlaybackTimer() }
    }
    
    private func jitterBufferFor(sender: String) -> JitterBuffer {
        if let existing = jitterBuffers[sender] { return existing }
        let newBuffer = JitterBuffer(maxDepth: 10) // Deeper buffer for stability
        jitterBuffers[sender] = newBuffer
        return newBuffer
    }
}
