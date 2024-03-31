import Foundation

struct DataPersistence {
    static let shared = DataPersistence()
    private let userDefaults = UserDefaults.standard
    
    private init() {}
    
    func getOpenAIAssistantsID() -> String? {
        return userDefaults.string(forKey: "OpenAIAssistants:ID")
    }
    
    func saveOpenAIAssistantsID(_ id: String) {
        userDefaults.set(id, forKey: "OpenAIAssistants:ID")
    }
    
    func eraseOpenAIAssistantsID() {
        userDefaults.removeObject(forKey: "OpenAIAssistants:ID")
    }
}
