import SwiftUI

struct ContentView: View {
    @State var prompt: String = ""
    @State var singleton: MainSingleton = .init()
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "sparkles")
                Text("How can I assist you today?")
                    .font(.largeTitle)
                    .bold()
            }.font(.largeTitle)
                .bold()
            
            TextField("Prompt G.A.I.A...", text: $prompt)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                Button(action: {
                    Task.detached {
                        self.singleton.newConversation()
                    }
                }, label: {
                    Text("New Conversation")
                })
                
                Button(action: {
                    Task.detached {
                        self.singleton.resetAssistant()
                    }
                }, label: {
                    Text("Reset")
                })
            }
            
            VStack {
                ForEach((0..<(singleton.chatThread.count ?? 0)), id: \.self) { index in
                    createViewForChatThreadItem(singleton.chatThread[index])
                    
                }
                
            }
        }
        .padding()
        .onAppear(perform: {
            singleton.initialize()
        })
    }
}

func createViewForChatThreadItem(_ item: ChatThreadItem) -> some View {
    switch item {
    case .action(let action):
        return Text("\(action.userDescription) - \(action.id)")
    case .text(let sender, let text):
        return Text("\(sender): \(text.text)")
    }
}

#Preview {
    ContentView()
}
