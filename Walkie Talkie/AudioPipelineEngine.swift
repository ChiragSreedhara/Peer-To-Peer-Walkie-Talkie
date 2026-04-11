import Foundation
import AVFoundation
import Combine

final class AudioPipelineEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {

    @Published private(set) var isTransmitting = false
    @Published private(set) var isPlaying = false

    var onAudioPacketReady: ((Data) -> Void)?

    // MARK: - Engine components
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let codec = OpusCodecWrapper()

    private var sampleAccumulator: [Float] = []
    private let frameSize = Int(AudioConstants.frameSamples)
    private var converter: AVAudioConverter?

    private var livePlaybackTimer: Timer?

    private var audioPlayer: AVAudioPlayer?

    override init() {
        super.init()
        configureAudioSession()
        setupAudioEngine()
    }

    // MARK: - Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setPreferredSampleRate(Double(AudioConstants.sampleRate))
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: AudioConstants.pcmFormat)

        audioEngine.prepare()

        let inputNode = audioEngine.inputNode
        let hwFormat  = inputNode.outputFormat(forBus: 0)

        if hwFormat.sampleRate != AudioConstants.sampleRate || hwFormat.channelCount != AudioConstants.channels {
            converter = AVAudioConverter(from: hwFormat, to: AudioConstants.pcmFormat)
        }

        inputNode.installTap(onBus: 0, bufferSize: 512, format: hwFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine: Failed to start — \(error)")
        }
    }

    // MARK: - Transmitting

    func startTransmitting() {
        guard !isTransmitting else { return }
        sampleAccumulator.removeAll()
        DispatchQueue.main.async { self.isTransmitting = true }
    }

    func stopTransmitting() {
        guard isTransmitting else { return }
        DispatchQueue.main.async { self.isTransmitting = false }
    }

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isTransmitting else { return }

        let monoBuffer: AVAudioPCMBuffer
        if let converter = converter {
            let outputFrameCapacity = AVAudioFrameCount(
                ceil(Double(buffer.frameLength) * AudioConstants.sampleRate / buffer.format.sampleRate)
            ) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: AudioConstants.pcmFormat,
                                                   frameCapacity: outputFrameCapacity) else { return }
            var convError: NSError?
            var consumed = false
            converter.convert(to: converted, error: &convError) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                consumed = true
                return buffer
            }
            guard convError == nil else { return }
            monoBuffer = converted
        } else {
            monoBuffer = buffer
        }

        guard let floatData = monoBuffer.floatChannelData?[0] else { return }
        for i in 0..<Int(monoBuffer.frameLength) {
            sampleAccumulator.append(floatData[i])
        }

        while sampleAccumulator.count >= frameSize {
            let chunk = Array(sampleAccumulator.prefix(frameSize))
            sampleAccumulator.removeFirst(frameSize)
            encodeAndSend(chunk)
        }
    }

    private func encodeAndSend(_ samples: [Float]) {
        guard let frameBuffer = AVAudioPCMBuffer(pcmFormat: AudioConstants.pcmFormat,
                                                 frameCapacity: AVAudioFrameCount(frameSize)) else { return }
        frameBuffer.frameLength = AVAudioFrameCount(frameSize)
        samples.withUnsafeBufferPointer {
            frameBuffer.floatChannelData![0].update(from: $0.baseAddress!, count: frameSize)
        }
        guard let encoded = codec.encode(pcmBuffer: frameBuffer) else { return }
        onAudioPacketReady?(encoded)
    }

    // MARK: - Live streaming playback

    func enqueueLiveFrame(_ opusData: Data) {
        guard let pcmBuffer = codec.decode(compressedData: opusData) else { return }
        playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        playerNode.play()
        DispatchQueue.main.async {
            self.isPlaying = true
            self.livePlaybackTimer?.invalidate()
            self.livePlaybackTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.isPlaying = false }
            }
        }
    }

    // MARK: - Async voice-note playback (inbox)

    func playVoiceNote(_ data: Data) {
        do {
            if isPlaying { audioPlayer?.stop() }
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            DispatchQueue.main.async { self.isPlaying = true }
        } catch {
            print("AudioEngine: Failed to play voice note — \(error)")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.isPlaying = false }
    }
}
