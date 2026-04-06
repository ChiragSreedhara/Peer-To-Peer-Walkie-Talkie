//
//  AudioPipelineEngine.swift
//  Walkie Talkie
//
//  Created by Nicole Li on 4/5/26.
//
//
//  Audio Processing Layer - Main Engine
//
//  This class sits between the UI (push-to-talk button) and the Mesh Routing
//  Engine (Layer 3). It handles:
//
//    SEND PATH:  Mic → AVAudioEngine tap → Opus encode → AudioPacket → serialize → mesh
//    RECV PATH:  mesh → deserialize → JitterBuffer → Opus decode → AVAudioPlayerNode → speaker
//
//  Usage from the UI / ContentView:
//
//    let audio = AudioPipelineEngine()
//    audio.onAudioPacketReady = { packetData in
//        meshRouter.broadcast(payload: packetData)
//    }
//
//    // When push-to-talk button is pressed:
//    audio.startTransmitting()
//
//    // When push-to-talk button is released:
//    audio.stopTransmitting()
//
//    // When a payload arrives from the mesh:
//    audio.receiveAudioData(payloadData, from: senderName)
//

import AVFoundation
import UIKit
import Combine

final class AudioPipelineEngine: ObservableObject {
    
    // MARK: - Public State
    
    /// True while the mic is hot and we're sending audio.
    @Published private(set) var isTransmitting = false
    
    /// True while we're actively playing back received audio.
    @Published private(set) var isReceiving = false
    
    /// Callback: hand serialized AudioPacket bytes to the mesh layer for broadcast.
    var onAudioPacketReady: ((Data) -> Void)?
    
    // MARK: - Audio Engine Components
    
    private let captureEngine = AVAudioEngine()
    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    // MARK: - Codec & Buffer
    
    private let codec: AudioCodec = OpusCodecWrapper()
    private var jitterBuffers: [String: JitterBuffer] = [:]  // per-sender
    
    // MARK: - Sequencing
    
    private var sequenceCounter: UInt32 = 0
    
    // MARK: - Playback Timer
    
    private var playbackTimer: DispatchSourceTimer?
    private let playbackQueue = DispatchQueue(label: "com.walkietalkie.playback")
    
    // MARK: - Init
    
    init() {
        setupPlaybackEngine()
    }
    
    // MARK: - Audio Session
    
    private func configureAudioSession(forCapture: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if forCapture {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            } else {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setPreferredSampleRate(AudioConstants.sampleRate)
            try session.setPreferredIOBufferDuration(
                Double(AudioConstants.frameSamples) / AudioConstants.sampleRate
            )
            try session.setActive(true)
        } catch {
            print("AudioPipeline: Failed to configure audio session — \(error)")
        }
    }
    
    // MARK: - Send Path (Mic → Encode → Mesh)
    
    func startTransmitting() {
        guard !isTransmitting else { return }
        
        configureAudioSession(forCapture: true)
        
        let inputNode = captureEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // We need to convert the hardware format → our canonical 16 kHz mono format.
        guard let targetFormat = AudioConstants.pcmFormat as AVAudioFormat?,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("AudioPipeline: Cannot create format converter.")
            return
        }
        
        let frameSamples = AudioConstants.frameSamples
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, _) in
            guard let self = self else { return }
            
            // Convert to 16 kHz mono
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameSamples
            ) else { return }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            guard status != .error, error == nil else {
                print("AudioPipeline: Conversion error — \(error?.localizedDescription ?? "unknown")")
                return
            }
            
            convertedBuffer.frameLength = min(convertedBuffer.frameLength, frameSamples)
            
            // Encode
            guard let compressedData = self.codec.encode(pcmBuffer: convertedBuffer) else { return }
            
            // Wrap in AudioPacket
            let packet = AudioPacket(
                sequenceNumber: self.sequenceCounter,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                frameDurationMs: AudioConstants.frameDurationMs,
                senderID: UIDevice.current.name,
                opusData: compressedData
            )
            self.sequenceCounter += 1
            
            // Serialize and hand off to the mesh
            if let serialized = packet.serialize() {
                self.onAudioPacketReady?(serialized)
            }
        }
        
        do {
            try captureEngine.start()
            DispatchQueue.main.async { self.isTransmitting = true }
            print("AudioPipeline: 🎙️ Transmitting started")
        } catch {
            print("AudioPipeline: Failed to start capture engine — \(error)")
        }
    }
    
    func stopTransmitting() {
        guard isTransmitting else { return }
        captureEngine.inputNode.removeTap(onBus: 0)
        captureEngine.stop()
        sequenceCounter = 0
        DispatchQueue.main.async { self.isTransmitting = false }
        print("AudioPipeline: 🎙️ Transmitting stopped")
    }
    
    // MARK: - Receive Path (Mesh → Decode → Speaker)
    
    /// Called by the mesh routing engine whenever an audio payload arrives.
    func receiveAudioData(_ data: Data, from senderName: String) {
        guard let packet = AudioPacket.deserialize(from: data) else {
            print("AudioPipeline: Failed to deserialize AudioPacket from \(senderName)")
            return
        }
        
        // Get or create a per-sender jitter buffer
        let buffer = jitterBufferFor(sender: senderName)
        buffer.insert(packet)
        
        // Start the playback pump if it's not already running
        startPlaybackTimerIfNeeded()
    }
    
    // MARK: - Playback Engine Setup
    
    private func setupPlaybackEngine() {
        playbackEngine.attach(playerNode)
        
        let format = AudioConstants.pcmFormat
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: format)
        
        do {
            try playbackEngine.start()
            playerNode.play()
        } catch {
            print("AudioPipeline: Failed to start playback engine — \(error)")
        }
    }
    
    // MARK: - Playback Timer
    
    /// A repeating timer that drains all jitter buffers every 20 ms (one frame period)
    /// and schedules decoded PCM for playback.
    private func startPlaybackTimerIfNeeded() {
        guard playbackTimer == nil else { return }
        
        DispatchQueue.main.async { self.isReceiving = true }
        
        // Ensure playback engine is running
        if !playbackEngine.isRunning {
            try? playbackEngine.start()
            playerNode.play()
        }
        
        let timer = DispatchSource.makeTimerSource(queue: playbackQueue)
        let intervalMs = Int(AudioConstants.frameDurationMs)
        timer.schedule(
            deadline: .now() + .milliseconds(intervalMs * 3),  // initial fill delay
            repeating: .milliseconds(intervalMs)
        )
        
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
    
    /// Drain one frame from each active jitter buffer, decode it, and schedule for playback.
    private func drainBuffersAndPlay() {
        var anyActive = false
        
        for (senderName, buffer) in jitterBuffers {
            guard let packet = buffer.dequeue() else { continue }
            anyActive = true
            
            guard let pcmBuffer = codec.decode(compressedData: packet.opusData) else {
                print("AudioPipeline: Decode failed for packet \(packet.sequenceNumber) from \(senderName)")
                continue
            }
            
            // Schedule the decoded audio on the player node
            playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }
        
        // If all buffers are exhausted for a while, stop the timer to save resources.
        if !anyActive {
            // Simple heuristic: stop after seeing no data.
            // A production app might wait longer before stopping.
            stopPlaybackTimer()
            print("AudioPipeline: All jitter buffers drained. Playback paused.")
        }
    }
    
    // MARK: - Helpers
    
    private func jitterBufferFor(sender: String) -> JitterBuffer {
        if let existing = jitterBuffers[sender] {
            return existing
        }
        let newBuffer = JitterBuffer(maxDepth: 5)
        jitterBuffers[sender] = newBuffer
        return newBuffer
    }
    
    /// Clean up resources.
    func shutdown() {
        stopTransmitting()
        stopPlaybackTimer()
        captureEngine.stop()
        playbackEngine.stop()
    }
}
