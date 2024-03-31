import Foundation
import SwiftOpenAI

func openAICreateAssistant(actions: [Action], service: OpenAIService) async -> String? {
    let actionsAsOpenAITools: [AssistantObject.Tool] = actions.map { action in
        .init(type: .function, function: actionToOpenAIFunction(action))
    }
    
    let uuid = UUID()
    let parameters = AssistantParameters(
        action: .create(model: Model.gpt4TurboPreview.value),
        name: "gaia-\(uuid)-assistant",
        description: "Personal Gaia Assistant for user \(uuid)",
        instructions: "You are Gaia, a capable on-device AI assistant. You are provided functions to perform system operations and fulfill the user's requests effectively. Please do not say you are unable to complete tasks. You are indirectly controlling a macOS system, for which you have complete access via your \"function calls\". Break down every request the user provides into these function calls. For example, if the user would like to send an email to someone, use your system operation to first get a contact's E-mail; then, send the email to the returned email address.",
        tools: actionsAsOpenAITools + [
            .init(type: .codeInterpreter),
        ],
        fileIDS: nil,
        metadata: nil
    )
    
    if let assistant = try? await service.createAssistant(parameters: parameters) {
        print("Success \(assistant)")
        return assistant.id
    } else {
        return nil
    }
}
