protocol TextToSpeech {
    func stop()
    func prepare()
    func speakText(_ str: String, waitUntilOutput: Bool) async -> Void
}
