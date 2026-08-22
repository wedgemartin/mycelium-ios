import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()
    var loraSource: String? = nil // name of LoRA that was active during generation
    
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
    @Environment(\.peerManager) var peerManager
    @Environment(\.speechService) var speech
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    @State private var streamingText = ""
    @State private var pullingKnowledge = false
    @State private var pullingName = ""
    @State private var showLibrary = false
    @State private var showAbout = false
    @State private var showActiveAdapters = false
    
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
                                MessageBubble(message: msg) {
                                    showLibrary = true
                                }
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .sheet(isPresented: $showLibrary) {
                NavigationStack {
                    LoRALibraryView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showLibrary = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showActiveAdapters) {
                ActiveAdaptersView()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        showAbout = true
                    } label: {
                        Text("Mycelium")
                            .font(.system(size: 18, design: .serif))
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    let activeCount = loraManager.installed.filter(\.isActive).count
                    if activeCount > 0 {
                        Button {
                            showActiveAdapters = true
                        } label: {
                            Text("\(activeCount) 🧠")
                                .font(.system(size: 14, design: .monospaced))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        speech.isEnabled.toggle()
                        if !speech.isEnabled { speech.stop() }
                    } label: {
                        Image(systemName: speech.isEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            .foregroundColor(speech.isEnabled ? .purple : .gray)
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
                
                // Start P2P peer discovery on local network
                let installedHashes = loraManager.installed.map(\.hash)
                peerManager.start(address: tempAddress, installedHashes: installedHashes)
                peerManager.onLoRAReceived = { hash, data in
                    if let lora = network.catalog.first(where: { $0.hash == hash }) {
                        loraManager.install(lora: lora, data: data)
                    }
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
            
            // Step 3: Download any missing LoRAs (P2P first, then bot)
            if !uninstalled.isEmpty {
                pullingKnowledge = true
                pullingName = uninstalled.map(\.name).joined(separator: ", ")
                
                // Download sequentially (limit to top 2 most relevant)
                for needed in uninstalled.prefix(2) {
                    pullingName = needed.name
                    
                    // Try P2P first — check if any local peer has this LoRA
                    if let peer = peerManager.peerWith(loraHash: needed.hash) {
                        print("mycelium: 🔄 requesting \(needed.name) from local peer \(peer.host)")
                        await withCheckedContinuation { continuation in
                            peerManager.onLoRAReceived = { hash, data in
                                if hash == needed.hash {
                                    self.loraManager.install(lora: needed, data: data)
                                    continuation.resume()
                                }
                            }
                            peerManager.requestLoRA(hash: needed.hash, from: peer)
                        }
                    } else {
                        // Fall back to bot via DERP
                        print("mycelium: no local peer has \(needed.name), falling back to bot")
                        await withCheckedContinuation { continuation in
                            network.onLoRADownloaded = { [self] lora, data in
                                loraManager.install(lora: lora, data: data)
                                continuation.resume()
                            }
                            network.downloadLoRA(hash: needed.hash)
                        }
                    }
                }
                pullingKnowledge = false
                let pulledNames = uninstalled.map(\.name).joined(separator: ", ")
                pullingName = ""
                
                // Add a persistent note in chat showing what was pulled
                var pullMsg = ChatMessage(role: .assistant, content: "🍄 Pulled knowledge from the network: \(pulledNames)")
                pullMsg.loraSource = nil // no attribution on the system message itself
                messages.append(pullMsg)
            }
            
            // Step 4: Deactivate all, then activate only the top matches for THIS query
            for lora in loraManager.installed where lora.isActive {
                loraManager.deactivate(lora: lora, engine: engine)
            }
            for match in matches.prefix(2) {
                if let installed = loraManager.installed.first(where: { $0.hash == match.hash }) {
                    loraManager.activate(lora: installed, engine: engine)
                }
            }
            
            // Step 5: Run inference with all relevant LoRAs active
            runInference()
        }
    }
    
    private func runInference() {
        let ttsPrompt: String? = speech.isEnabled
            ? "Answer concisely in 1-2 sentences. Be direct and brief."
            : nil
        Task {
            await engine.generate(messages: messages, systemPrompt: ttsPrompt) { token in
                Task { @MainActor in
                    streamingText += token
                }
            }
            
            // Tag response with active LoRAs
            let activeNames = loraManager.installed.filter(\.isActive).map(\.name)
            var response = ChatMessage(role: .assistant, content: streamingText)
            response.loraSource = activeNames.isEmpty ? nil : activeNames.joined(separator: " + ")
            messages.append(response)
            speech.speak(response.content)
            streamingText = ""
            isGenerating = false
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var onLoRATap: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.purple : Color(.systemGray5))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)
                
                if let source = message.loraSource {
                    Button {
                        onLoRATap?()
                    } label: {
                        Text("🍄 via \(source)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.purple.opacity(0.7))
                            .padding(.horizontal, 4)
                    }
                }
            }
            
            if message.role == .assistant { Spacer() }
        }
    }
}
