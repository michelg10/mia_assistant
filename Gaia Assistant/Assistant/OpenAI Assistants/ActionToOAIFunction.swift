import Foundation
import SwiftOpenAI

/// Converts an `ActionDataType` to a `ChatCompletionParameters.ChatFunction.JSONSchema.Property`.
///
/// This function recursively converts the given `ActionDataType` to its corresponding JSON schema representation.
/// It handles various types such as arrays, optionals, integers, doubles, booleans, and strings.
///
/// - Parameters:
///   - type: The `ActionDataType` to convert.
///   - shouldIgnoreOptional: A boolean indicating whether to ignore the optional wrapping of the type.
///     On the top level, whether a field is optional is already specified by the `required` property,
///     making the optional wrapping redundant.
///
/// - Returns: The converted `ChatCompletionParameters.ChatFunction.JSONSchema.Property` representing the JSON schema
///   for the given `ActionDataType`.
fileprivate func typeToJson(type: ActionDataType, shouldIgnoreOptional: Bool) -> ChatCompletionParameters.ChatFunction.JSONSchema.Property {
    switch type {
    case .array(let of):
        return .init(
            type: .array,
            items: typeToJson(type: of, shouldIgnoreOptional: false)
        )
    case .optional(let of):
        let internalJson = typeToJson(type: of, shouldIgnoreOptional: false)
        if shouldIgnoreOptional {
            return internalJson
        } else {
            return .init(type: nil, anyOf: [
                .init(type: .null),
                internalJson
            ])
        }
    case .int:
        return .init(type: .integer)
    case .double:
        return .init(type: .number)
    case .bool:
        return .init(type: .boolean)
    case .string:
        return .init(type: .string)
    }
}

fileprivate func inputToJson(_ inputParameter: Action.InputParameter) -> ChatCompletionParameters.ChatFunction.JSONSchema.Property {
    let result = typeToJson(type: inputParameter.type, shouldIgnoreOptional: true)
    
    return result.withDescription(inputParameter.description)
}

func actionToOpenAIFunction(_ action: Action) -> ChatCompletionParameters.ChatFunction {
    let requiredInputIdentifiers = action.inputs.filter { inputParameter in
        if case .optional(_) = inputParameter.type {
            return false
        }
        return true
    }.map { inputParameter in
        inputParameter.identifier
    }
    
    return .init(
        name: action.identifier,
        description: action.description,
        parameters: .init(
            type: .object,
            properties: action.inputs.reduce(into: [String: ChatCompletionParameters.ChatFunction.JSONSchema.Property]()) { dict, inputParameter in
                dict[inputParameter.identifier] = inputToJson(inputParameter)
            },
            required: requiredInputIdentifiers
        )
    )
}
