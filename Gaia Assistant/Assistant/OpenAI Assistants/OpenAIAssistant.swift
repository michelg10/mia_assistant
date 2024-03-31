import Foundation
import SwiftOpenAI
import SwiftData

@Observable
class OpenAIAssistant: Assistant {
    let service: OpenAIService
    let assistantID: String
    let availableActions: [Action]
    var actionIdToActionMap: [String : Action] = [:]
    var threadID: String? = nil
    // The ID of the next thread to use
    var nextThreadID: String? = nil
    var mainObject: AssistantMainObject?
    var chatThread: [ChatThreadItem] = [] {
        didSet {
            self.pushThreadToMain()
        }
    }
    
    private func pushThreadToMain() {
        guard let mainObject = self.mainObject else {
            return
        }
        
        mainObject.setChatThread(chatThread)
    }
    
    required init(actions: [Action]) async {
        self.availableActions = actions
        let apiKey = OpenAIAPIKey
        self.service = OpenAIServiceFactory.service(apiKey: apiKey)
        
        // Retrieve a session ID from disk, if it exists.
        if let assistantID = DataPersistence.shared.getOpenAIAssistantsID() {
            // should probably perform some checks on whether or not I need to update the assistant for production use, but skipped for now.
            self.assistantID = assistantID
        } else {
            // Create new Assistant
            guard let resultingID = await openAICreateAssistant(actions: actions, service: service) else {
                fatalError("Could not create new OpenAI Assistant")
            }
            
            self.assistantID = resultingID
            DataPersistence.shared.saveOpenAIAssistantsID(self.assistantID)
        }
        
        print("Assistant ID \(assistantID)")
        
        self.availableActions.forEach { action in
            actionIdToActionMap[action.identifier] = action
        }
    }
    
    func resetAssistantID() {
        DataPersistence.shared.eraseOpenAIAssistantsID()
    }
    
    func reset() {
        self.resetAssistantID()
        fatalError() // TODO: Reload class instead of crashing
    }
    
    func prepareForNewConversation() async {
        // Create OpenAI Assistants Thread
        guard nextThreadID == nil else {
            return
        }
        
        self.chatThread = []
        
        let parameters = CreateThreadParameters()
        let thread = try? await service.createThread(parameters: parameters)
        if nextThreadID == nil {
            nextThreadID = thread?.id
        }
    }
    
    func handleUserQuery(message: String) async {
        self.chatThread.append(.text(.user, .init(text: message)))
        self.pushThreadToMain()
        
        if threadID == nil {
            // TODO: Error handling
            threadID = nextThreadID!
        }
        
        let messageParameter = MessageParameter(
            role: .user,
            content: message
        )
        
        // TODO: Error handling
        try! await service.createMessage(
            threadID: self.threadID!,
            parameters: messageParameter
        )
        
        // Performs a single Assistant run loop and returns whether or not the Assistant is finished
        struct ActionToRun {
            var openAIId: String
            var name: String
            var arguments: String
        }
        
        func runAssistant(withRunStream stream: AsyncThrowingStream<AssistantStreamEvent, any Error>) async -> (String, Bool, [ActionToRun]) {
            // TODO: Error handling
            var actionsToRun: [ActionToRun] = []
            var continueCallingAssistant = false
            var currentRunId = ""
            
            do {
                // Records the index of the previous tool call to identify when a new tool call has begun
                var previousToolCallIndex: Int?
                var assistantWritingInProgressActionCall: ActionToRun? = nil
                
                for try await chunk in stream {
                    switch chunk {
                    case .threadRunStepDelta(let runStepDelta):
                        // Tool call
                        let deltaStepDetails = runStepDelta.delta.stepDetails
                        assert(deltaStepDetails.type == "tool_calls")
                        
                        let toolCalls = deltaStepDetails.toolCalls!
                        
                        for toolCall in toolCalls {
                            if toolCall.index != previousToolCallIndex {
                                // New tool call
                                let newToolInternalID = UUID().uuidString
                                let newToolOpenAIID = toolCall.id!
                                previousToolCallIndex = toolCall.index
                                // TODO: If need be, somehow record the internal ID and the OpenAI ID
                                
                                if let assistantWritingInProgressActionCallUnwrapped = assistantWritingInProgressActionCall {
                                    self.chatThread.append(.action(.init(id: newToolInternalID, userDescription: "Running action \(assistantWritingInProgressActionCallUnwrapped.name)")))
                                    self.pushThreadToMain()
                                    actionsToRun.append(assistantWritingInProgressActionCallUnwrapped)
                                    assistantWritingInProgressActionCall = nil
                                }
                                
                                if toolCall.type == "code_interpreter" {
                                    self.chatThread.append(.action(.init(id: newToolInternalID, userDescription: "Running Python...")))
                                    self.pushThreadToMain()
                                } else if toolCall.type == "function" {
                                    assistantWritingInProgressActionCall = .init(openAIId: newToolOpenAIID, name: "", arguments: "")
                                }
                            }
                            
                            if toolCall.type == "function" {
                                var functionToolCallParameters: FunctionToolCall?
                                switch toolCall.toolCall {
                                case .functionToolCall(let functionToolCall):
                                    functionToolCallParameters = functionToolCall
                                default:
                                    break
                                }
                                
                                if let functionToolCallParameters = functionToolCallParameters {
                                    if let nameDelta = functionToolCallParameters.name {
                                        assistantWritingInProgressActionCall!.name += nameDelta
                                    }
                                    assistantWritingInProgressActionCall!.arguments += functionToolCallParameters.arguments
                                } else {
                                    assertionFailure("Expect function call run step delta to include function tool call parameters")
                                }
                            } else if toolCall.type == "code_interpreter" {
                                // long term, we'll accumulate tokens here to update a progress bar. But that's not what we need rn, so we skip!
                                // do nothing for now.
                            }
                        }
                        break
                    case .threadMessageDelta(let threadMessageDelta):
                        let currentText: String
                        switch chatThread.last! {
                        case .text(let sender, let innerText):
                            currentText = innerText.text
                        case .action(_):
                            currentText = ""
                            assertionFailure("Expected text to be last item for MessageDelta!")
                        }
                        assert(threadMessageDelta.delta.content.count == 1)
                        
                        let deltaContent = threadMessageDelta.delta.content[0]
                        let deltaText: String
                        switch deltaContent {
                        case .imageFile(_):
                            assertionFailure("Expected delta content to be text")
                            deltaText = ""
                        case .text(let innerText):
                            deltaText = innerText.text.value
                        }
                        self.chatThread[self.chatThread.count - 1] = .text(.assistant, .init(text: currentText + deltaText))
                        self.pushThreadToMain()
                    case .threadMessageCreated:
                        self.chatThread.append(.text(.assistant, .init(text: "")))
                        self.pushThreadToMain()
                    case .threadRunRequiresAction:
                        continueCallingAssistant = true
                    case .threadRunCreated(let runId):
                        currentRunId = runId
                    default:
                        print("Unexpected chunk: \(chunk)")
                        break
                    }
                }
                print("Stream done")
                
                print(self.chatThread)
                
                if let assistantWritingInProgressActionCall = assistantWritingInProgressActionCall {
                    let newToolInternalID = UUID().uuidString
                    actionsToRun.append(assistantWritingInProgressActionCall)
                    self.chatThread.append(.action(.init(id: newToolInternalID, userDescription: "Running action \(assistantWritingInProgressActionCall.name)")))
                    self.pushThreadToMain()
                }
            } catch {
                print("Error: \(error)")
            }
                        
            return (currentRunId, continueCallingAssistant, actionsToRun)
        }
        
        // Perform run loop
        var isInitialRun = true
        var previousRunId: String?
        var previousToolOutputs: [RunToolsOutputParameter.ToolOutput]? = nil
        while true {
            let toContinue: Bool, actionsToRun: [ActionToRun]
            
            if isInitialRun {
                let parameters: RunParameter = .init(assistantID: self.assistantID)
                let stream = try! await service.createRunStream(threadID: self.threadID!, parameters: parameters)
                (previousRunId, toContinue, actionsToRun) = await runAssistant(withRunStream: stream)
            } else {
                let parameters: RunToolsOutputParameter = .init(toolOutputs: previousToolOutputs!)
                let stream = try! await service.submitToolOutputsToRunStream(threadID: self.threadID!, runID: previousRunId!, parameters: parameters)
                (previousRunId, toContinue, actionsToRun) = await runAssistant(withRunStream: stream)
            }
            isInitialRun = false
            
            print("RUN ASSISTANT RESULTS - \(toContinue), \(actionsToRun)")
            
            if !toContinue {
                break
            }
            
            // Parse the action's parameters.
            // TODO: Error handling
            let correspondingActions: [Action] = actionsToRun.map { actionToRun in
                self.actionIdToActionMap[actionToRun.name]!
            }
            
            let actionInputs: [[Any?]] = actionsToRun.enumerated().map { (index, actionToRun) in
                let action = correspondingActions[index]
                let providedParametersMap = jsonStringToDict(actionToRun.arguments)!
                let inputParameters = action.inputs.map { inputParameter in
                    providedParametersMap[inputParameter.identifier]
                }
                return inputParameters
            }
            
            // TODO: Fill in all of this for user confirmations, descriptions, progress updates, etc.
            let actionPerformParameters: [Action.ActionPerformParameters] = (0..<actionsToRun.count).map { index in
                .init(
                    inputs: actionInputs[index],
                    presentUserConfirmation: { confirmationDisplay in
                        print("User confirmation display attempt: \(confirmationDisplay)")
                        return true // the user gave true!
                    },
                    setDescription: { newDescription in
                        print("New description set: \(newDescription)")
                    },
                    updateContinuousProgress: { newProgress in
                        print("Progress update: \(newProgress)")
                    }
                )
            }
            
            var actionResults: [Any?] = .init(repeating: nil, count: actionsToRun.count)
            
            // Executing them all concurrently comes up with issues because the shortcuts try to write to the same file at once.
            for (index, action) in correspondingActions.enumerated() {
                actionResults[index] = await action.perform(actionPerformParameters[index])
            }
            
            previousToolOutputs = (0..<actionsToRun.count).map({ index in
                return .init(
                    toolCallId: actionsToRun[index].openAIId,
                    output: representValueAsStringForJson(actionResults[index])
                )
            })
            
            print("Tool outputs \(previousToolOutputs)")
        }
    }
    
    func registerMainObject(_ object: any AssistantMainObject) {
        self.mainObject = object
    }
    
    private func syncChatThread() {
        self.mainObject!.setChatThread(self.chatThread)
    }
}
