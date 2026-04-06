//
//  AudioCodec.swift
//  Walkie Talkie
//
//  Created by Nicole Li on 4/5/26.
//
//  Audio Processing Layer - Codec Abstraction
//
//  Provides a protocol for audio encoding/decoding
//

import AVFoundation
import Opus


protocol AudioCodec {
    /// Encode a single PCM buffer into compressed bytes.
    func encode(pcmBuffer: AVAudioPCMBuffer) -> Data?
    
    /// Decode compressed bytes back into a PCM buffer.
    func decode(compressedData: Data) -> AVAudioPCMBuffer?
}


enum AudioConstants {
    /// 16 kHz mono — standard narrowband voice.
    static let sampleRate: Double = 16_000
    static let channels: AVAudioChannelCount = 1
    
    /// 20 ms frame at 16 kHz = 320 samples.
    static let frameSamples: AVAudioFrameCount = 320
    static let frameDurationMs: UInt16 = 20
    
    /// Opus target bitrate in bits/s (48 kbps is a good voice sweet-spot).
    static let opusBitrate: Int32 = 48_000
    
    /// The canonical PCM format used everywhere in the audio pipeline.
    static var pcmFormat: AVAudioFormat {
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
    }
}


final class OpusCodecWrapper: AudioCodec {
    
    private var encoder: OpaquePointer?
    private var decoder: OpaquePointer?
    
    private let maxPacketSize = 1275  // Opus max packet
    
    init() {
         var encoderError: Int32 = 0
         encoder = opus_encoder_create(
             Int32(AudioConstants.sampleRate),
             Int32(AudioConstants.channels),
             OPUS_APPLICATION_VOIP,
             &encoderError
         )
         guard encoderError == OPUS_OK else {
             fatalError("Opus encoder init failed: \(encoderError)")
         }
         opus_encoder_set_bitrate(encoder!, AudioConstants.opusBitrate)
        
         var decoderError: Int32 = 0
         decoder = opus_decoder_create(
             Int32(AudioConstants.sampleRate),
             Int32(AudioConstants.channels),
             &decoderError
         )
         guard decoderError == OPUS_OK else {
             fatalError("Opus decoder init failed: \(decoderError)")
         }
        
        print("AudioCodec: OpusCodecWrapper initialized (link libopus to activate)")
    }
    
    func encode(pcmBuffer: AVAudioPCMBuffer) -> Data? {
         guard let encoder = encoder,
               let floatData = pcmBuffer.floatChannelData?[0] else { return nil }
        
         let frameSize = Int32(pcmBuffer.frameLength)
        
         // Convert Float32 -> Int16 for Opus
         var pcm16 = [Int16](repeating: 0, count: Int(frameSize))
         for i in 0..<Int(frameSize) {
             let clamped = max(-1.0, min(1.0, floatData[i]))
             pcm16[i] = Int16(clamped * Float(Int16.max))
         }
        
         var outputBuffer = [UInt8](repeating: 0, count: maxPacketSize)
         let encodedBytes = opus_encode(
             encoder,
             pcm16,
             frameSize,
             &outputBuffer,
             Int32(maxPacketSize)
         )
        
         guard encodedBytes > 0 else { return nil }
         return Data(outputBuffer[0..<Int(encodedBytes)])
    }
    
    func decode(compressedData: Data) -> AVAudioPCMBuffer? {
         guard let decoder = decoder else { return nil }
        
         let frameSize = Int32(AudioConstants.frameSamples)
         var pcm16 = [Int16](repeating: 0, count: Int(frameSize))
        
         let decodedSamples = compressedData.withUnsafeBytes { rawPtr -> Int32 in
             let ptr = rawPtr.bindMemory(to: UInt8.self).baseAddress!
             return opus_decode(
                 decoder,
                 ptr,
                 Int32(compressedData.count),
                 &pcm16,
                 frameSize,
                 0  // no FEC
             )
         }
        
         guard decodedSamples > 0 else { return nil }
        
         let format = AudioConstants.pcmFormat
         guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(decodedSamples)) else { return nil }
         buffer.frameLength = AVAudioFrameCount(decodedSamples)
        
         // Convert Int16 -> Float32
         let outFloat = buffer.floatChannelData![0]
         for i in 0..<Int(decodedSamples) {
             outFloat[i] = Float(pcm16[i]) / Float(Int16.max)
         }
        
         return buffer
    }
    
    deinit {
         opus_encoder_destroy(encoder)
         opus_decoder_destroy(decoder)
    }
}
