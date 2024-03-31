import Foundation

@Observable
class MainSingleton: VoiceCommandProcessorMainObject, AssistantMainObject {
    func setChatThread(_ thread: [ChatThreadItem]) {
        self.chatThread = thread
    }
    
    func appendTextChunk(_ text: String) {
        guard let lastMessage = self.chatThread.last else {
            return
        }
        
        var lastMessageText = ""
        var lastMessageSender: ChatThreadItem.Sender = .assistant
        switch lastMessage {
        case .text(let sender, let text):
            lastMessageText = text.text
            lastMessageSender = sender
        case .action(let action):
            lastMessageText = ""
        }
        
        self.chatThread.popLast()
        self.chatThread.append(.text(lastMessageSender, .init(text: lastMessageText + text)))
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
                self.chatThread.append(.text(.user, .init(text: currentCommand)))
                await self.assistant!.handleUserQuery(message: currentCommand)
                currentCommand = ""
            }
        }
    }
    
    func resetAssistant() {
        self.assistant!.reset()
    }
}
