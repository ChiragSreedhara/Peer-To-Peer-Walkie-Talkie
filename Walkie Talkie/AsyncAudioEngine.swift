import Foundation
import AVFoundation
import Combine
import UIKit

final class AsyncAudioEngine: NSObject, ObservableObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    
    @Published private(set) var isTransmitting = false
    @Published private(set) var isPlaying = false
    
    var onAudioPacketReady: ((Data) -> Void)?

    private(set) var sentCount: UInt32 = 0
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    
    private let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent("voicenote.m4a")
    
    override init() {
        super.init()
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }
    
    func startTransmitting() {
        guard !isTransmitting else { return }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record(forDuration: 3.0)
                    
            DispatchQueue.main.async { self.isTransmitting = true }
            audioPlayer?.stop()
            DispatchQueue.main.async { self.isPlaying = false }
        } catch {
            print("AudioEngine couldnt start recording. The error is \(error)")
        }
    }
    
    func stopTransmitting() {
        guard isTransmitting else { return }
        audioRecorder?.stop()
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async { self.isTransmitting = false }

        guard flag, let audioData = try? Data(contentsOf: recordURL) else { return }

        sentCount += 1
        let packet = AsyncAudioPacket(
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            senderID: UIDevice.current.name,
            totalSent: sentCount,
            audioData: audioData
        )

        DispatchQueue.global(qos: .userInitiated).async {
            if let serialized = packet.serialize() {
                self.onAudioPacketReady?(serialized)
             }
        }
    }
    
    func playVoiceNote(_ data: Data) {
        if isPlaying {
            audioPlayer?.stop()
        }
        
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            
            
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            DispatchQueue.main.async { self.isPlaying =true }
        } catch {
            print("AudioEngine: Failed to play voice note - \(error)")
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.isPlaying = false }
    }
}
