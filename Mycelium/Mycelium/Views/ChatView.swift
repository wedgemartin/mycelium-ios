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
    @State private var recognizer = SpeechRecognizer()
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    @State private var streamingText = ""
    @State private var pullingKnowledge = false
    @State private var pullingName = ""
    @State private var showLibrary = false
    @State private var showAbout = false
    @State private var showActiveAdapters = false
    @State private var showTrainingWizard = false
    @State private var hasShownPublishNudge = false
    @State private var showTestChat = false
    @State private var testChatHash = ""
    @State private var testChatName = ""
    
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
                HStack(spacing: 10) {
                    // Mic button (speech-to-text)
                    Button {
                        toggleDictation()
                    } label: {
                        Image(systemName: recognizer.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 22))
                            .foregroundColor(recognizer.isListening ? .red : .purple)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(isGenerating)
                    
                    TextField("Message...", text: $inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(white: 0.2))
                        .cornerRadius(20)
                        .overlay(alignment: .topTrailing) {
                            if !inputText.isEmpty {
                                Button {
                                    inputText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .padding(8)
                                }
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .navigationDestination(isPresented: $showLibrary) {
                LoRALibraryView()
            }
            .sheet(isPresented: $showActiveAdapters) {
                ActiveAdaptersView()
            }
            .sheet(isPresented: $showTrainingWizard) {
                #if os(macOS)
                TrainingWizardView()
                #else
                EmptyView()
                #endif
            }
            #if os(macOS)
            .navigationDestination(isPresented: $showTestChat) {
                TestChatView(loraHash: testChatHash, loraName: testChatName)
            }
            #endif
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
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 12) {
                        Menu {
                            #if os(macOS)
                            Button {
                                showTrainingWizard = true
                            } label: {
                                Label("Train New Adapter", systemImage: "brain")
                            }
                            #else
                            Link(destination: URL(string: "https://apps.apple.com/app/mycelium-ai/id6803590299")!) {
                                Label("Train on Mac", systemImage: "desktopcomputer")
                            }
                            #endif
                            Button {
                                showLibrary = true
                            } label: {
                                Label("Library", systemImage: "square.stack.3d.up")
                            }
                            Divider()
                            Button {
                                showAbout = true
                            } label: {
                                Label("About", systemImage: "info.circle")
                            }
                            Divider()
                            Link(destination: URL(string: "https://mycelium.getspore.xyz/privacy.html")!) {
                                Label("Privacy Policy", systemImage: "lock.shield")
                            }
                            Link(destination: URL(string: "https://mycelium.getspore.xyz/terms.html")!) {
                                Label("Terms of Service", systemImage: "doc.text")
                            }
                            Link(destination: URL(string: "https://mycelium.getspore.xyz/safety.html")!) {
                                Label("Safety & Reporting", systemImage: "shield")
                            }
                            Link(destination: URL(string: "https://mycelium.getspore.xyz/support.html")!) {
                                Label("Support", systemImage: "questionmark.circle")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16))
                        }
                        
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
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        speech.isEnabled.toggle()
                        if !speech.isEnabled { speech.stop() }
                    } label: {
                        Image(systemName: speech.isEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            .foregroundColor(speech.isEnabled ? .purple : .gray)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
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
                
                // Listen for Test & Rate requests from Library
                NotificationCenter.default.addObserver(forName: .init("openTestChat"), object: nil, queue: .main) { notification in
                    if let info = notification.userInfo,
                       let hash = info["hash"] as? String,
                       let name = info["name"] as? String {
                        testChatHash = hash
                        testChatName = name
                        showTestChat = true
                    }
                }
                
                // Listen for vote requests from Library
                NotificationCenter.default.addObserver(forName: .init("loraVote"), object: nil, queue: .main) { notification in
                    if let info = notification.userInfo,
                       let hash = info["hash"] as? String,
                       let vote = info["vote"] as? String {
                        network.sendVote(hash: hash, vote: vote)
                    }
                }
                
                // Listen for report requests
                NotificationCenter.default.addObserver(forName: .init("loraReport"), object: nil, queue: .main) { notification in
                    if let hash = notification.userInfo?["hash"] as? String {
                        network.sendReport(hash: hash, reason: "user_reported")
                        network.hideAdapter(hash)
                    }
                }
                
                // Listen for block requests
                NotificationCenter.default.addObserver(forName: .init("loraBlock"), object: nil, queue: .main) { notification in
                    if let pubkey = notification.userInfo?["pubkey"] as? String {
                        network.blockPublisher(pubkey)
                    }
                }
                
                // Reconcile orphaned/hash-named adapters with real catalog metadata
                network.onCatalogUpdated = { catalog in
                    loraManager.reconcileWithCatalog(catalog)
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
    
    private func toggleDictation() {
        if recognizer.isListening {
            recognizer.stop()
        } else {
            // Stop TTS if it's speaking so we don't record our own voice
            speech.stop()
            recognizer.onTranscript = { text in
                inputText = text
            }
            recognizer.start()
        }
    }
    
    private func sendMessage() {
        // Stop dictation if active
        if recognizer.isListening { recognizer.stop() }
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
            
            // Only consider the top 2 most relevant matches (already sorted by score)
            let top2 = Array(matches.prefix(2))
            print("mycelium: top 2 = \(top2.map(\.name))")
            
            // Of the top 2, which need downloading?
            let uninstalled = top2.filter { match in
                !loraManager.installed.contains(where: { $0.hash == match.hash })
            }
            print("mycelium: \(uninstalled.count) of top 2 not yet installed")
            
            // Step 3: Download any missing top-2 LoRAs (P2P first, then bot)
            if !uninstalled.isEmpty {
                pullingKnowledge = true
                pullingName = uninstalled.map(\.name).joined(separator: ", ")
                
                for needed in uninstalled {
                    pullingName = needed.name
                    var installed = false

                    // Tier 1: a peer we already know has it (LAN mDNS or a live QUIC peer).
                    if let peer = peerManager.peerWith(loraHash: needed.hash) {
                        print("mycelium: 🔄 requesting \(needed.name) from peer \(peer.host) [\(peer.transport)]")
                        await downloadWithTimeout(seconds: 30) { done in
                            peerManager.onLoRAReceived = { hash, data in
                                if hash == needed.hash {
                                    self.loraManager.install(lora: needed, data: data)
                                    installed = true
                                    done()
                                }
                            }
                            peerManager.requestLoRA(hash: needed.hash, from: peer)
                        }
                    }

                    // Tier 2: no known peer — try to reach holders directly over the
                    // internet (STUN hole-punch → QUIC). The substrate tells us which peers
                    // hold this LoRA; the publisher is always a candidate seeder too.
                    if !installed {
                        var seeders = needed.holders
                        if !needed.authorPubkey.isEmpty, needed.authorPubkey != network.botAddress,
                           !seeders.contains(needed.authorPubkey) {
                            seeders.append(needed.authorPubkey)
                        }
                        if !seeders.isEmpty {
                            print("mycelium: 🌐 attempting direct P2P from \(seeders.count) seeder(s)")
                            for addr in seeders.prefix(3) {
                                peerManager.connectToInternetPeer(addr: addr)
                            }
                            await downloadWithTimeout(seconds: 20) { done in
                                peerManager.onLoRAReceived = { hash, data in
                                    if hash == needed.hash {
                                        self.loraManager.install(lora: needed, data: data)
                                        installed = true
                                        done()
                                    }
                                }
                                // Give hole-punch a moment, then request from whichever peer connected.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                                    if let peer = self.peerManager.peerWith(loraHash: needed.hash) {
                                        self.peerManager.requestLoRA(hash: needed.hash, from: peer)
                                    }
                                }
                            }
                        }
                    }

                    // Tier 3: bot as seeder-of-last-resort (DERP).
                    if !installed {
                        print("mycelium: no peer served \(needed.name), falling back to bot (seeder-of-last-resort)")
                        await downloadWithTimeout(seconds: 30) { done in
                            network.onLoRADownloaded = { [self] lora, data in
                                loraManager.install(lora: lora, data: data)
                                done()
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
                    let path = loraManager.localPath(for: installed)
                    print("⚡️ ACTIVATE: '\(installed.name)' hash=\(installed.hash.prefix(12)) localFile=\(path != nil ? "✅" : "❌ MISSING")")
                    loraManager.activate(lora: installed, engine: engine)
                } else {
                    print("⚡️ ACTIVATE: match '\(match.name)' NOT in installed list — needs download")
                }
            }
            let activeNow = loraManager.installed.filter(\.isActive).map(\.name)
            print("⚡️ ACTIVE after step 4: \(activeNow)")
            
            // Step 5: Run inference with all relevant LoRAs active
            runInference()
        }
    }
    /// Run a download closure that must call done(); resolves after done() or a timeout, whichever comes first.
    private func downloadWithTimeout(seconds: Double, _ start: (@escaping () -> Void) -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finished = NSLock()
            var done = false
            func resume() {
                finished.lock(); defer { finished.unlock() }
                guard !done else { return }
                done = true
                continuation.resume()
            }
            start { resume() }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                print("mycelium: ⏱️ download timed out after \(Int(seconds))s")
                resume()
            }
        }
    }

    
    private func runInference() {
        let ttsPrompt: String? = speech.isEnabled
            ? "Answer concisely in 1-2 sentences. Be direct and brief."
            : nil
        speech.beginStreaming()
        Task {
            await engine.generate(messages: messages, systemPrompt: ttsPrompt) { token in
                Task { @MainActor in
                    streamingText += token
                    speech.feedToken(token)
                }
            }
            
            // Tag response with active LoRAs
            let activeNames = loraManager.installed.filter(\.isActive).map(\.name)
            var response = ChatMessage(role: .assistant, content: streamingText)
            response.loraSource = activeNames.isEmpty ? nil : activeNames.joined(separator: " + ")
            messages.append(response)
            speech.endStreaming()
            
            // Show publish nudge if a local-only LoRA contributed
            let hasLocalActive = loraManager.installed.filter(\.isActive).contains(where: \.isLocal)
            if hasLocalActive && !hasShownPublishNudge {
                hasShownPublishNudge = true
                let nudge = ChatMessage(role: .assistant, content: "🍄 Happy with the results? You can publish this adapter to the Spore network from your Library (☰ → Library → Publish).")
                messages.append(nudge)
            }
            
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
                    .background(message.role == .user ? Color.purple : Color(white: 0.2))
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
