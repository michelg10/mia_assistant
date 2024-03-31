extension BuiltInActions {
    func fetchEmails() -> Action {
        return .init(
            identifier: "fetch_latest_email",
            description: "Fetches the sender, subject, and body of my latest received email",
            inputs: [
            ],
            output: .init(
                type: .array(of: .string),
                description: "The sender, subject, and body of the latest received email"
            ),
            displayTitle: "Fetch Latest Email",
            defaultProgressDescription: "Fetching email...",
            progressIndicatorType: .indeterminate,
            perform: { parameters in
                
                let result = runShortcutActionCrude(name: "Assistant - Fetch Latest Email", inputs: [:])
                
                var contacts = result.components(separatedBy: "\n")
                
                return contacts
            }
        )
    }
}
