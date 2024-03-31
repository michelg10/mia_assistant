import Foundation

func jsonStringToDict(_ jsonString: String) -> [String : Any]? {
    guard let data = jsonString.data(using: .utf8) else {
        print("Failed to convert JSON string to data")
        return nil
    }

    do {
        if let jsonDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            return jsonDict
        }
    } catch {
        print("Failed to decode JSON:", error)
    }
    return nil
}
