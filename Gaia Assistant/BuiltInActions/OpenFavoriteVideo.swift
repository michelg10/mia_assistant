extension BuiltInActions {
    func openFavoriteVideo() -> Action {
        return .init(
            identifier: "open_favorite_video",
            description: "Opens my favorite video.",
            inputs: [],
            output: .init(
                type: .string,
                description: "The status of if the video was successfully opened or not."
            ),
            displayTitle: "Open Favorite Video",
            defaultProgressDescription: "Opening Video...",
            progressIndicatorType: .indeterminate,
            perform: { parameters in
                let result = runShortcutActionCrude(name: "Assistant - Open Favorite Video", inputs: [:])
                
                return result
            }
        )
    }
}
