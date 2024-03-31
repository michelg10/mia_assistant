extension BuiltInActions {
    func getContacts() -> Action {
        return .init(
            identifier: "get_contact_email",
            description: "Searches for the contacts in your library that match the given criteria",
            inputs: [
                .init(
                    type: .optional(of: .string),
                    displayTitle: "Name",
                    identifier: "name",
                    description: "Finds the emails of contacts with names containing the given string. Leave empty to fetch all contacts. Capitalize the names."
                ),
                .init(
                    type: .optional(of: .int),
                    displayTitle: "Limit",
                    identifier: "limit",
                    description: "Limit search to a small number of contacts"
                )
            ],
            output: .init(
                type: .array(of: .string),
                description: "The full names and emails of contacts that match the search"
            ),
            displayTitle: "Get Contact Email",
            defaultProgressDescription: "Searching Contacts",
            progressIndicatorType: .indeterminate,
            perform: { parameters in
                let name = parameters.inputs[0]
                let limit = parameters.inputs[1]
                
                var inputs: [String: Encodable] = [:]
                
                if let name = name as? String {
                    inputs["name"] = name
                }
                
                let result = runShortcutActionCrude(name: "Assistant - Get Contact Email", inputs: inputs)
                
                var contacts = result.components(separatedBy: "\n")
                
                if let limitValue = limit as? Int {
                    contacts = Array(contacts.prefix(limitValue))
                }
                
                return contacts
            }
        )
    }
}
