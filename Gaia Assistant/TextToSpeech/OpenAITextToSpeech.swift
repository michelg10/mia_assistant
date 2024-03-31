import Foundation
import AVFoundation
import SwiftOpenAI

class OpenAITextToSpeech: TextToSpeech {
    let service: OpenAIService
    private let delayBetweenPlayback: Double = 0.4
    
    init() {
        let apiKey = OpenAIAPIKey
        self.service = OpenAIServiceFactory.service(apiKey: apiKey)
    }
    
    struct SpeechAudio {
        let data: Data
        let length: Double
        let playStartTime: Date
    }
    
    private var queued: [SpeechAudio] = []
    private var currentlyPlaying: SpeechAudio?
    private var currentPlayStartTime: Date?
    private var audioPlayer: AVAudioPlayer?
    
    func stop() {
        self.queued = []
        stopCurrentlyPlaying()
    }
    
    func prepare() {
        queued = []
    }
    
    func stopCurrentlyPlaying() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlaying = nil
        currentPlayStartTime = nil
    }
    
    struct SpeechCreationQueueElement {
        let str: String
        let id: String
    }
    private var speechCreationQueue: [SpeechCreationQueueElement] = []
    func createSpeech(_ str: String) async -> Data {
        let id = UUID().uuidString
        speechCreationQueue.append(.init(str: str, id: id))
                
        while (speechCreationQueue.first?.id != id) {
            try! await Task.sleep(nanoseconds: 100000)
        }
        
        let parameters = AudioSpeechParameters(model: .tts1, input: str, voice: .nova)
        let audioObjectData: Data = try! await service.createSpeech(parameters: parameters).output
        
        Task.detached {
            try! await Task.sleep(nanoseconds: 100000000)
            self.speechCreationQueue.removeFirst()
        }
        
        print("Get data")
        
        return audioObjectData
    }
    
    func speakText(_ str: String, waitUntilOutput: Bool = false) async {
        let audioObjectData = await createSpeech(str)
        
        let audioPlayer = try! AVAudioPlayer(data: audioObjectData)
        let duration = audioPlayer.duration
        
        var playDate: Date
        if queued.isEmpty {
            playDate = .now
        } else {
            let lastAudio = queued.last!
            playDate = lastAudio.playStartTime.advanced(by: lastAudio.length).advanced(by: delayBetweenPlayback)
        }
        
        let currentAudio: SpeechAudio = .init(data: audioObjectData, length: duration, playStartTime: playDate)
        queued.append(currentAudio)
        
        if currentlyPlaying == nil {
            Task.detached {
                await self.playNextInQueue()
            }
        } else {
            if waitUntilOutput {
                // sleep for currentAudio.playStartTime + length - .now
                let playFinishTime = currentAudio.playStartTime.addingTimeInterval(currentAudio.length)
                let sleepDuration = playFinishTime.timeIntervalSince(.now)
                try! await Task.sleep(for: .seconds(sleepDuration))
            } else {
                // nothing. An active playNextInQueue should have everything covered.
            }
        }
    }
    
    private func playNextInQueue() async {
        guard !queued.isEmpty else { return }
        
        stopCurrentlyPlaying()
        
        let nextAudio = queued.removeFirst()
        currentlyPlaying = nextAudio
        currentPlayStartTime = Date()
        
        audioPlayer = try! AVAudioPlayer(data: nextAudio.data)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
        
        let sleepFor: Duration
        if queued.isEmpty {
            sleepFor = .seconds(nextAudio.length + delayBetweenPlayback)
        } else {
            sleepFor = .seconds(queued.first!.playStartTime.timeIntervalSince(.now))
        }
        
        try! await Task.sleep(for: sleepFor)
        
        await playNextInQueue()
    }
}
