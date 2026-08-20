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
    @Environment(\.networkManager) var network
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    @State private var streamingText = ""
    @State private var pullingKnowledge = false
    @State private var pullingName = ""
    
    private let greetings = [
        "What can I help you with today?",
        "Ask me anything — I'm running locally on your device.",
        "What's on your mind?",
        "How can I help? All processing happens on-device.",
        "Ready when you are. No cloud, no tracking, just us."
    ]
    @State private var greeting = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                MessageBubble(message: ChatMessage(role: .assistant, content: greeting))
                                    .padding(.top, 40)
                            }
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            if pullingKnowledge {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("🍄 Pulling knowledge: \(pullingName)...")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.purple)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(12)
                                .id("pulling")
                            }
                            if isGenerating && streamingText.isEmpty && !pullingKnowledge {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 12)
                                .id("spinner")
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
                    ZStack(alignment: .trailing) {
                        TextField("Message...", text: $inputText, axis: .vertical)
                            .lineLimit(1...5)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .padding(.trailing, inputText.isEmpty ? 0 : 28)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                        
                        if !inputText.isEmpty {
                            Button {
                                inputText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .padding(.trailing, 10)
                        }
                    }
                    
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
                if greeting.isEmpty {
                    greeting = greetings.randomElement()!
                }
                if let path = modelManager.modelPath {
                    engine.loadModel(path: path)
                    // Re-apply any LoRAs that were active before restart
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        for lora in loraManager.installed where lora.isActive {
                            loraManager.activate(lora: lora, engine: engine)
                        }
                    }
                }
                // Connect to Spore network for LoRA discovery
                // TODO: Use real identity - for now use a temp address
                let tempAddress = "spore1mycelium\(Int.random(in: 1000...9999))"
                network.connect(address: tempAddress)
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
            // Step 1: Use the model to extract relevant search tags
            // TODO: Get actual city from device location
            let city = "São Paulo" // placeholder — wire to CoreLocation later
            let tags = await engine.extractTags(query: text, city: city)
            print("mycelium: query='\(text.prefix(40))' → tags=\(tags)")
            print("mycelium: catalog has \(network.catalog.count) entries")
            
            // Step 2: Match extracted tags against the LoRA catalog
            let matches = network.matchQuery(text, extractedTags: tags)
            print("mycelium: matched \(matches.count) LoRAs: \(matches.map(\.name))")
            let uninstalled = matches.filter { match in
                !loraManager.installed.contains(where: { $0.hash == match.hash })
            }
            print("mycelium: \(uninstalled.count) not yet installed")
            
            if let needed = uninstalled.first {
                // Found relevant knowledge on the network — pull it first
                pullingKnowledge = true
                pullingName = needed.name
                
                network.onLoRADownloaded = { [self] lora, data in
                    loraManager.install(lora: lora, data: data)
                    loraManager.activate(lora: lora, engine: engine)
                    pullingKnowledge = false
                    pullingName = ""
                    runInference()
                }
                network.downloadLoRA(hash: needed.hash)
            } else {
                // Auto-activate matching installed LoRA if not active
                if let match = matches.first(where: { m in loraManager.installed.contains(where: { $0.hash == m.hash }) }),
                   let installed = loraManager.installed.first(where: { $0.hash == match.hash }),
                   !installed.isActive {
                    loraManager.activate(lora: installed, engine: engine)
                }
                runInference()
            }
        }
    }
    
    private func runInference() {
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
