import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()
    
    enum Role {
        case user
        case assistant
    }
}

struct ChatView: View {
    @EnvironmentObject var modelManager: ModelManager
    @Environment(\.llamaEngine) var engine
    @Environment(\.loraManager) var loraManager
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    @State private var streamingText = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            if isGenerating && !streamingText.isEmpty {
                                MessageBubble(message: ChatMessage(role: .assistant, content: streamingText))
                                    .id("streaming")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: streamingText) { _, _ in
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                
                Divider()
                
                // Input
                HStack(spacing: 12) {
                    TextField("Message...", text: $inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                    
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(inputText.isEmpty || isGenerating ? .gray : .purple)
                    }
                    .disabled(inputText.isEmpty || isGenerating)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Mycelium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let activeCount = loraManager.installed.filter(\.isActive).count
                    if activeCount > 0 {
                        Text("\(activeCount) LoRA\(activeCount == 1 ? "" : "s")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        LoRALibraryView()
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.purple)
                    }
                }
            }
            .onAppear {
                if let path = modelManager.modelPath {
                    engine.loadModel(path: path)
                }
            }
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        inputText = ""
        isGenerating = true
        streamingText = ""
        
        Task {
            await engine.generate(messages: messages) { token in
                Task { @MainActor in
                    streamingText += token
                }
            }
            
            let response = ChatMessage(role: .assistant, content: streamingText)
            messages.append(response)
            streamingText = ""
            isGenerating = false
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
            Text(message.content)
                .padding(12)
                .background(message.role == .user ? Color.purple : Color(.systemGray5))
                .foregroundColor(message.role == .user ? .white : .primary)
                .cornerRadius(16)
            
            if message.role == .assistant { Spacer() }
        }
    }
}
