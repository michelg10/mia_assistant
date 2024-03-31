extension BuiltInActions {
    func sendEmail() -> Action {
        return .init(
            identifier: "send_email",
            description: "Sends an email to a specified email address, with a subject and a body.",
            inputs: [
                .init(
                    type: .string,
                    displayTitle: "Recipient",
                    identifier: "recipient",
                    description: "Recipient of the email, in email address form (example@domain.com)."
                ),
                .init(
                    type: .string,
                    displayTitle: "Subject",
                    identifier: "subject",
                    description: "Subject line for the email."
                ),
                .init(
                    type: .string,
                    displayTitle: "Body",
                    identifier: "body",
                    description: "Message body of the email."
                ),
            ],
            output: .init(
                type: .string,
                description: "The status of if the email was successfully sent or not"
            ),
            displayTitle: "Send Email",
            defaultProgressDescription: "Sending email...",
            progressIndicatorType: .indeterminate,
            perform: { parameters in
                let recipient = parameters.inputs[0]
                let subject = parameters.inputs[1]
                let body = parameters.inputs[2]

                var inputs: [String: Encodable] = [:]
                
                inputs["recipient"] = recipient as! String
                inputs["subject"] = subject as! String
                inputs["body"] = body as! String
                
                let result = runShortcutActionCrude(name: "Assistant - Send Email", inputs: inputs)

                return result
            }
        )
    }
}
