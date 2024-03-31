import Foundation

@Observable
class MainSingleton: VoiceCommandProcessorMainObject, AssistantMainObject {
    func setChatThread(_ thread: [ChatThreadItem]) {
        self.chatThread = thread
    }
    
    private var textToSpeechBufferedText = ""
    private var textToSpeech: TextToSpeech?
    
    private func speakText(_ text: String) async {
        await textToSpeech!.speakText(text, waitUntilOutput: false)
    }
    
    private func textToSpeechReset() {
        self.textToSpeech!.stop()
        self.textToSpeechBufferedText = ""
    }
    
    func newTextChunk(_ text: String) {
        textToSpeechBufferedText.append(text)
        if textToSpeechBufferedText.contains(".") {
            let sentenceEnd = textToSpeechBufferedText.lastIndex(of: ".")!
            let textToSpeechSpeak = String(self.textToSpeechBufferedText[...sentenceEnd])
            Task.detached {
                await self.speakText(textToSpeechSpeak)
            }
            let newBuffer = String(self.textToSpeechBufferedText[self.textToSpeechBufferedText.index(after: sentenceEnd)...])
            if newBuffer.first?.isWhitespace == true {
                self.textToSpeechBufferedText = String(newBuffer.dropFirst())
            } else {
                self.textToSpeechBufferedText = newBuffer
            }
        }
    }
    
    func updateActionProgress(id: String, tokenCount: Int) {
        print("Request update action progress for \(id), token count \(tokenCount)")
    }
    
    func updateActionText(id: String, text: String) {
        print("Request action text for \(id), new text \(text)")
    }
    
    func getAssistantStateForVoiceCommandProcessor() async -> VoiceCommandProcessorAssistantState {
        // TODO
        return .inactive
    }
    
    func getConversationContextForVoiceCommandProcessor() -> [VoiceCommandProcessorMainSingletonContextMessage] {
        // TODO
        return []
    }
    
    private var transcriber: Transcriber? = nil
    private var voiceCommandProcessor: VoiceCommandProcessor? = nil
    private var assistant: Assistant? = nil
    
    let supportedActions: [Action] = [
        BuiltInActions().getContacts(),
        BuiltInActions().fetchEmails(),
        BuiltInActions().sendEmail(),
        BuiltInActions().openFavoriteVideo()
    ]
    
    func initialize() {
        Task.detached {
            if self.textToSpeech == nil {
                self.textToSpeech = OpenAITextToSpeech()
                self.textToSpeech!.prepare()
            }
            
            if self.voiceCommandProcessor == nil {
                self.voiceCommandProcessor = OpenAIVoiceCommandProcessor()
                self.voiceCommandProcessor?.registerMainObject(self)
            }
            
            if self.assistant == nil {
                self.assistant = await OpenAIAssistant(actions: self.supportedActions)
                self.assistant!.registerMainObject(self)
                await self.assistant!.prepareForNewConversation()
            }
            
            if self.transcriber == nil {
                self.transcriber = WhisperTranscriber()
                try! await self.transcriber!.startTranscription()
                Task.detached {
                    for try await chunk in self.transcriber!.getTranscribedChunksStream() {
                        await self.handleNewVoiceChunk(chunk)
                    }
                }
            }
        }
    }
    
    func newConversation() {
        Task.detached {
            self.textToSpeechReset()
            await self.assistant!.prepareForNewConversation()
        }
    }
    
    private var currentCommand: String = ""
    var chatThread: [ChatThreadItem] = []
    
    private func handleNewVoiceChunk(_ chunk: TranscribedChunk) async {
        // send to processor
        let commands = await self.voiceCommandProcessor!.processNewVoiceChunk([chunk])
        print("Received commands \(commands)")
        for command in commands {
            switch command {
            case .StartCommand:
                currentCommand = ""
            case .TextChunk(let chunkData):
                currentCommand += chunkData
            case .EndCommand:
                self.textToSpeechReset()
                self.chatThread.append(.text(.user, .init(text: currentCommand)))
                await self.assistant!.handleUserQuery(message: currentCommand)
                currentCommand = ""
            }
        }
    }
    
    func resetAssistant() {
        self.textToSpeechReset()
        self.assistant!.reset()
    }
}
