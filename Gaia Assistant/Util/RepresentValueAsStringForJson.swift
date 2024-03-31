func representValueAsStringForJson(_ value: Any?) -> String {
    guard let value = value else {
        return "null"
    }
    
    if let value = value as? String {
        return value.debugDescription
    } else if let value = value as? Int {
        return String(value)
    } else if let value = value as? Double {
        return String(value)
    } else if let value = value as? Bool {
        return value ? "true" : "false"
    } else if let array = value as? [Any] {
        let jsonArray = array.map { representValueAsStringForJson($0) }.joined(separator: ", ")
        return "[\(jsonArray)]"
    } else {
        return "null"
    }
}
