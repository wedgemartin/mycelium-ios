#if os(macOS)
import SwiftUI
import Combine

/// A dedicated chat for testing a locally-trained LoRA with thumbs up/down feedback.
/// Ratings are collected as training signal for optional retraining.
struct TestChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.llamaEngine) var engine
    @Environment(\.loraManager) var loraManager
    @Environment(\.speechService) var speech
    
    let loraHash: String
    let loraName: String
    @StateObject private var feedback = FeedbackCollector()
    
    @State private var inputText = ""
    @State private var messages: [RatedMessage] = []
    @State private var isGenerating = false
    @State private var streamingText = ""
    @State private var showRetrainConfirm = false
    @State private var isRetraining = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with LoRA info + rating count
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Testing: \(loraName)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        Text("\(feedback.totalCount) of 10 ratings needed • \(feedback.approvedCount) 👍 \(feedback.rejectedCount) 👎")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    Spacer()
                    if feedback.totalCount >= 10 {
                        Button {
                            showRetrainConfirm = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Retrain")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.55, green: 0.37, blue: 0.24))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(red: 0.55, green: 0.37, blue: 0.24).opacity(0.05))
                
                Divider()
                
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.text.bubble.right")
                                        .font(.system(size: 36))
                                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24).opacity(0.5))
                                    Text("Ready to test!")
                                        .font(.headline)
                                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                                    Text("Ask questions about the topic you trained on.\nRate each response with 👍 or 👎.")
                                        .font(.subheadline)
                                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 60)
                            }
                            
                            ForEach(messages) { message in
                                TestMessageBubble(message: message) { rating in
                                    rateMessage(message, rating: rating)
                                }
                            }
                            
                            if !streamingText.isEmpty {
                                HStack {
                                    Text(streamingText)
                                        .font(.body)
                                        .padding(12)
                                        .background(Color(white: 0.2))
                                        .cornerRadius(12)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                            
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        proxy.scrollTo("bottom")
                    }
                    .onChange(of: streamingText) { _, _ in
                        proxy.scrollTo("bottom")
                    }
                }
                
                // Input
                HStack(spacing: 8) {
                    TextField("Ask something to test your adapter...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }
                        .disabled(isGenerating)
                    
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(inputText.isEmpty || isGenerating ? .gray : Color(red: 0.55, green: 0.37, blue: 0.24))
                    }
                    .disabled(inputText.isEmpty || isGenerating)
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 2, y: -1)
            }
            .background(Color(red: 0.976, green: 0.965, blue: 0.949))
            .frame(minWidth: 500, minHeight: 600)
            .preferredColorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("Test & Rate")
                        .font(.system(size: 16, design: .serif))
                        .fontWeight(.semibold)
                }
            }
            .alert("Retrain with feedback?", isPresented: $showRetrainConfirm) {
                Button("Retrain") { retrain() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will retrain the adapter using your \(feedback.approvedCount) approved responses and excluding \(feedback.rejectedCount) rejected ones. Training takes ~10 minutes.")
            }
            .onAppear {
                activateLoRA()
                feedback.loraHash = loraHash
                // Restore previous messages
                if messages.isEmpty && !feedback.messages.isEmpty {
                    messages = feedback.messages
                }
            }
            .onDisappear { deactivateLoRA() }
        }
    }
    
    private func activateLoRA() {
        print("testchat: looking for LoRA with hash '\(loraHash)' in \(loraManager.installed.count) installed adapters")
        if let lora = loraManager.installed.first(where: { $0.hash == loraHash }) {
            print("testchat: found '\(lora.name)', activating...")
            loraManager.activate(lora: lora, engine: engine)
        } else {
            // Fallback: try to load directly by path
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let path = docs.appendingPathComponent("loras/\(loraHash).gguf").path
            if FileManager.default.fileExists(atPath: path) {
                print("testchat: hash not in installed list but file exists, loading directly: \(path)")
                engine.loadLoRA(path: path)
            } else {
                print("testchat: LoRA not found! hash=\(loraHash), installed=\(loraManager.installed.map(\.hash))")
            }
        }
    }
    
    private func deactivateLoRA() {
        if let lora = loraManager.installed.first(where: { $0.hash == loraHash }) {
            loraManager.deactivate(lora: lora, engine: engine)
        }
    }
    
    private func send() {
        guard !inputText.isEmpty, !isGenerating else { return }
        let question = inputText
        inputText = ""
        
        let userMsg = RatedMessage(role: .user, content: question)
        messages.append(userMsg)
        isGenerating = true
        streamingText = ""
        
        Task {
            await engine.generate(messages: messages.map { ChatMessage(role: $0.role, content: $0.content) },
                                  systemPrompt: "Answer concisely in 1-3 sentences. Be accurate and direct. Do not speculate or add information you are not certain about.") { token in
                Task { @MainActor in
                    streamingText += token
                }
            }
            
            let responseMsg = RatedMessage(role: .assistant, content: streamingText, question: question)
            messages.append(responseMsg)
            feedback.messages = messages
            streamingText = ""
            isGenerating = false
        }
    }
    
    private func rateMessage(_ message: RatedMessage, rating: FeedbackRating) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].rating = rating
        feedback.messages = messages
        
        // Store the feedback (this also saves to disk)
        if let question = message.question {
            feedback.record(question: question, answer: message.content, rating: rating)
        }
    }
    
    private func retrain() {
        isRetraining = true
        // Post notification to trigger retraining with feedback data
        NotificationCenter.default.post(
            name: .init("retrainWithFeedback"),
            object: nil,
            userInfo: [
                "hash": loraHash,
                "approved": feedback.approved,
                "rejected": feedback.rejected
            ]
        )
        dismiss()
    }
}

// MARK: - Data Models

enum FeedbackRating {
    case none
    case approved
    case rejected
}

struct RatedMessage: Identifiable {
    let id = UUID()
    let role: ChatMessage.Role
    let content: String
    var question: String? = nil  // The user question this was answering
    var rating: FeedbackRating = .none
}

// MARK: - Feedback Collector

class FeedbackCollector: ObservableObject {
    @Published var approved: [(String, String)] = []  // (question, answer)
    @Published var rejected: [(String, String)] = []
    @Published var messages: [RatedMessage] = []
    
    var loraHash: String = "" {
        didSet { load() }
    }
    
    var totalCount: Int { approved.count + rejected.count }
    var approvedCount: Int { approved.count }
    var rejectedCount: Int { rejected.count }
    
    func record(question: String, answer: String, rating: FeedbackRating) {
        // Remove any previous rating for this Q&A
        approved.removeAll { $0.0 == question && $0.1 == answer }
        rejected.removeAll { $0.0 == question && $0.1 == answer }
        
        switch rating {
        case .approved:
            approved.append((question, answer))
        case .rejected:
            rejected.append((question, answer))
        case .none:
            break
        }
        
        // Persist
        UserDefaults.standard.set(totalCount, forKey: "ratings_\(loraHash)")
        save()
    }
    
    private var storageURL: URL? {
        guard !loraHash.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("feedback_\(loraHash).json")
    }
    
    private func save() {
        guard let url = storageURL else { return }
        let data: [String: Any] = [
            "approved": approved.map { ["q": $0.0, "a": $0.1] },
            "rejected": rejected.map { ["q": $0.0, "a": $0.1] },
            "messages": messages.map { [
                "role": $0.role == .user ? "user" : "assistant",
                "content": $0.content,
                "question": $0.question ?? "",
                "rating": $0.rating == .approved ? "approved" : $0.rating == .rejected ? "rejected" : "none"
            ] }
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            try? jsonData.write(to: url)
        }
    }
    
    private func load() {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        if let approvedArr = json["approved"] as? [[String: String]] {
            approved = approvedArr.compactMap { dict in
                guard let q = dict["q"], let a = dict["a"] else { return nil }
                return (q, a)
            }
        }
        if let rejectedArr = json["rejected"] as? [[String: String]] {
            rejected = rejectedArr.compactMap { dict in
                guard let q = dict["q"], let a = dict["a"] else { return nil }
                return (q, a)
            }
        }
        if let messagesArr = json["messages"] as? [[String: String]] {
            messages = messagesArr.map { dict in
                let role: ChatMessage.Role = dict["role"] == "user" ? .user : .assistant
                let rating: FeedbackRating = dict["rating"] == "approved" ? .approved :
                    dict["rating"] == "rejected" ? .rejected : .none
                var msg = RatedMessage(role: role, content: dict["content"] ?? "")
                msg.question = dict["question"]?.isEmpty == false ? dict["question"] : nil
                msg.rating = rating
                return msg
            }
        }
    }
}

// MARK: - Message Bubble with Rating

struct TestMessageBubble: View {
    let message: RatedMessage
    let onRate: (FeedbackRating) -> Void
    
    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .user { Spacer() }
                
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(message.role == .user
                        ? Color(red: 0.55, green: 0.37, blue: 0.24)
                        : Color(white: 0.95))
                    .foregroundColor(message.role == .user ? .white : Color(red: 0.1, green: 0.1, blue: 0.1))
                    .cornerRadius(12)
                
                if message.role == .assistant { Spacer() }
            }
            
            // Rating buttons (only for assistant messages)
            if message.role == .assistant {
                HStack(spacing: 12) {
                    Button {
                        onRate(.approved)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: message.rating == .approved ? "hand.thumbsup.fill" : "hand.thumbsup")
                            if message.rating == .approved {
                                Text("Good")
                                    .font(.caption2)
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundColor(message.rating == .approved ? .green : Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        onRate(.rejected)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: message.rating == .rejected ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            if message.rating == .rejected {
                                Text("Bad")
                                    .font(.caption2)
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundColor(message.rating == .rejected ? .red : Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal)
    }
}

#endif
