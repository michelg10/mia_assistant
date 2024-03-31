import AVFoundation
import Combine
import Foundation

class WhisperTranscriber: Transcriber {
    /* State variables */
    private var state: TranscriberState = .stopped
    private var recordingActive = false
    private let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

    private let audioEngine = AVAudioEngine()
    
    private let bus = 0

    private let thresholdLevel: Float = -45.0 // dBFS. To be adjustable
    private var lastLevel: Float = 0.0;
    
    private var transcriptionStartTime: Date?
    private var currTranscriptionStartTime: Date?

    private var audioDataBuffer = [Float]()
    
    private var transcribedChunksSubject = PassthroughSubject<TranscribedChunk, Error>()

    init() {
        try! setupAudioEngine()
    }
        
    func getState() -> TranscriberState {
        return state
    }

    func startTranscription() async throws {
        guard state == .stopped else {
            print("Trying to start an already started transcription")
            return
        }
        state = .starting
        try audioEngine.start()
        state = .running
    }
    
    func stopTranscription() async throws {
        guard state == .running else {
            print("Trying to stop a stopped transcription")
            return
        }
        
        recordingActive = false
        state = .stopping
        audioEngine.stop()
        state = .stopped
        recordingActive = false
    }
    
    private func setupAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: bus)
        inputNode.installTap(onBus: bus, bufferSize: 100000, format: inputFormat) { [weak self] (buffer, when) in
            self?.processAudioBuffer(buffer: buffer, when: when)
        }
        audioEngine.prepare()
    }
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        let level = analyzeAudioBuffer(buffer: buffer)
        print(level)

        if recordingActive {
            audioDataBuffer += extractAudioSamples(from: buffer)!
            
            if level <= thresholdLevel && lastLevel <= thresholdLevel {
                recordingActive = false
                let recordingEndTime = Date() // Get the current time when recording stops
                
                // Process the accumulated audio data for transcription
                transcribeAccumulatedAudioData(buffer: audioDataBuffer, startTime: transcriptionStartTime, endTime: recordingEndTime)

                transcriptionStartTime = nil
            }
            
        } else { // !recordingActive
            audioDataBuffer = extractAudioSamples(from: buffer)!

            if level > thresholdLevel {
                recordingActive = true
                transcriptionStartTime = Date()
            }
        }
        
        lastLevel = level
    }
    
    
    private func extractAudioSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let floatChannelData = buffer.floatChannelData else {
            // floatChannelData is nil, which means the buffer has no audio data.
            return nil
        }
    
        // The number of frames in the buffer.
        let frameLength = Int(buffer.frameLength)
        
        // The number of channels in the audio data.
        let channelCount = Int(buffer.format.channelCount)
        
        // Assuming that we are working with mono audio. For stereo or other multi-channel audio,
        // you would need to decide how to handle multiple channels.
        if channelCount > 1 {
            print("Warning: extractAudioSamples is currently implemented to handle mono audio only.")
        }
        
        // Get a pointer to the first channel in the audio data.
        let audioSamples = floatChannelData[0]
        
        // Initialize an array with the audio data from the first channel.
        let samples = Array(UnsafeBufferPointer(start: audioSamples, count: frameLength))
        
        return samples
    }

    private func transcribeAudioUsingWhisper(buffer: [Float]) async throws -> String {
        if buffer.count == 0 {
            return ""
        }
        // write out to file, invoke command-line whisper, read file back
        let id = UUID().uuidString
        let basePath = "/Users/michel/Desktop/WhisperBridge/"
        let inputFile = basePath + "\(id).wav"
        let outputFile = basePath + "\(id).txt"
        let outputFileWithoutExt = basePath + "\(id)"
        let modelPath = basePath + "whisper.cpp/models/ggml-medium-q5_0.bin"

        // Configure the audio format
        let sampleRate = 48000.0 / 3 // Standard CD-quality sample rate
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false)!

        // Create the audio file
        let fileURL = URL(fileURLWithPath: inputFile) // Choose your path and file format
        do {
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false)
            
            let count = buffer.count / 3
            
            // Create an AVAudioPCMBuffer from your float array
            let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            pcmBuffer.frameLength = UInt32(count)
            for i in 0..<count {
                let value = Int(buffer[3 * i] * 32767)
                
                pcmBuffer.int16ChannelData!.pointee[i] = Int16(min(max(value, -32767), 32767))
            }
            
            // Write the buffer to the file
            try audioFile.write(from: pcmBuffer)
            
            print("Audio file successfully written.")
        } catch {
            print("An error occurred: \(error)")
        }

        // invoke whisper
        let task = Process()
        task.launchPath = "\(basePath)whisper.cpp/main"
        task.arguments = ["-m", modelPath, "-otxt", "--output-file", outputFileWithoutExt, "-f", inputFile]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.launch()
        task.waitUntilExit()

        // Wait for output
        while !FileManager.default.fileExists(atPath: outputFile) {
            usleep(50000)
        }

        // Read back text and return
        let text = try String(contentsOfFile: outputFile)
        print("OUTPUT RESULT ", text)
        return text
    }
    
    private func transcribeAccumulatedAudioData(buffer: [Float], startTime: Date?, endTime: Date) {
        guard !audioDataBuffer.isEmpty else {
            return
        }

        Task {
            do {
                let transcription = try await transcribeAudioUsingWhisper(buffer: buffer) // use Whisper

                let chunk = TranscribedChunk(
                    text: transcription,
                    startTimestamp: startTime ?? Date(),
                    endTimestamp: endTime
                )

                // Emit the chunk to subscribers
                transcribedChunksSubject.send(chunk)
            } catch {
                transcribedChunksSubject.send(completion: .failure(error))
            }
        }
    }
    
    private func analyzeAudioBuffer(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return -100.0
        }
        let frameLength = Int(buffer.frameLength)
        let rms = (0..<frameLength).compactMap { channelData.pointee[$0] }.map { $0 * $0 }.reduce(0, +) / Float(frameLength)
        return 20 * log10(sqrt(rms))
    }
        
    func getTranscribedChunksStream() -> AsyncThrowingStream<TranscribedChunk, any Error> {
        AsyncThrowingStream<TranscribedChunk, Error> { continuation in
            // Subscription to the subject that emits new transcribed chunks
            let subscription = self.transcribedChunksSubject.sink(
                receiveCompletion: { completion in
                    // Handle the completion (either finished or failure with an error)
                    if case let .failure(error) = completion {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                },
                receiveValue: { chunk in
                    // Emit new chunks to the stream as they come in
                    continuation.yield(chunk)
                }
            )
            
            // Store the subscription so it doesn't get deallocated
            continuation.onTermination = { @Sendable _ in
                subscription.cancel()
            }
        }
    }
}

