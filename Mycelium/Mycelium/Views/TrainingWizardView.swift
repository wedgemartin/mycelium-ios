#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

enum TrainingStep {
    case source
    case review
    case training
}

enum SourceType {
    case rss
    case paste
    case file
}

struct TrainingWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var training = TrainingViewModel()
    
    var body: some View {
        NavigationStack {
            Group {
                switch training.step {
                case .source:
                    SourcePickerView(training: training)
                case .review:
                    ReviewConfigureView(training: training)
                case .training:
                    TrainingProgressView(training: training)
                }
            }
            .background(Color(red: 0.976, green: 0.965, blue: 0.949))
            .preferredColorScheme(.light)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if training.step == .source {
                        Button("Cancel") { dismiss() }
                    } else if training.step == .review {
                        Button("Back") { training.step = .source }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(training.step == .source ? "New Adapter" :
                         training.step == .review ? "Review" : "Training")
                        .font(.system(size: 16, design: .serif))
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Step 1: Source Picker

struct SourcePickerView: View {
    @ObservedObject var training: TrainingViewModel
    @State private var showFilePicker = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                #if os(iOS)
                // Mac recommendation
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Training works best on Mac")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        Text("Install Mycelium on your Mac for faster training with no restrictions.")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.55, green: 0.37, blue: 0.24).opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)
                #endif
                // Source type selector
                Picker("Source", selection: $training.sourceType) {
                    Text("RSS Feed").tag(SourceType.rss)
                    Text("Paste Text").tag(SourceType.paste)
                    Text("Import File").tag(SourceType.file)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 16)
                
                switch training.sourceType {
                case .rss:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter an RSS feed URL")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        TextField("https://example.com/feed", text: $training.rssURLInput)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                        Text("The feed's articles will be used to generate training data.")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    .padding(.horizontal)
                    
                case .paste:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste your text content")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        TextEditor(text: $training.pastedText)
                            .frame(minHeight: 200)
                            .border(Color(red: 0.88, green: 0.87, blue: 0.85), width: 1)
                            .cornerRadius(8)
                        Text("Minimum ~4,000 characters (3-4 pages of text)")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    .padding(.horizontal)
                    
                case .file:
                    VStack(spacing: 16) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                        Text("Import a text file")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        Text("Supported: .txt, .md, .csv")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        Button("Choose File") {
                            showFilePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.55, green: 0.37, blue: 0.24))
                        
                        if let fileName = training.importedFileName {
                            HStack {
                                Image(systemName: "doc.fill")
                                Text(fileName)
                                    .font(.subheadline)
                            }
                            .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                        }
                    }
                    .padding(.top, 40)
                }
                
                Spacer()
                
                // Next button
                Button {
                    switch training.sourceType {
                    case .rss:
                        training.sourceText = ""
                        training.rssURL = training.rssURLInput
                    case .paste:
                        training.sourceText = training.pastedText
                        training.rssURL = nil
                    case .file:
                        training.rssURL = nil
                    }
                    training.analyzeSource()
                } label: {
                    HStack {
                        if training.isAnalyzing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(training.isAnalyzing ? "Analyzing..." : "Next")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isNextEnabled ? Color(red: 0.55, green: 0.37, blue: 0.24) : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!isNextEnabled || training.isAnalyzing)
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.plainText, .commaSeparatedText, .text, .json, .data]) { result in
            if case .success(let url) = result {
                training.importFile(url: url)
            }
        }
    }
    
    private var isNextEnabled: Bool {
        switch training.sourceType {
        case .rss: return !training.rssURLInput.isEmpty
        case .paste: return training.pastedText.count > 4000
        case .file: return training.importedFileName != nil
        }
    }
}

// MARK: - Step 2: Review & Configure

struct ReviewConfigureView: View {
    @ObservedObject var training: TrainingViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Analysis results
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content Analysis")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    
                    HStack {
                        StatBadge(label: "Tokens", value: "\(training.tokenCount)")
                        StatBadge(label: "Articles", value: "\(training.articleCount)")
                        StatBadge(label: "Q&A Pairs", value: "~\(training.estimatedQAPairs)")
                    }
                    
                    // Quality gate
                    HStack(spacing: 8) {
                        Image(systemName: training.qualityPassed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(training.qualityPassed ? .green : .red)
                        Text(training.qualityMessage)
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                
                // Configuration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configure")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adapter Name")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        TextField("e.g. Bay Area Food Guide", text: $training.adapterName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tags (comma separated)")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        TextField("food, local, california", text: $training.tagsString)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                        Text("After training, test the adapter in chat. When you're happy with results, publish it from your Library.")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                
                // Estimated time
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "clock")
                        Text("Estimated training time: ~\(training.estimatedMinutes) minutes")
                    }
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                    
                    Text("Keep the app open or plug in to train overnight.")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                
                // Terms acceptance
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $training.acceptedTerms) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("I confirm I own this content")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                            Text("I have the rights to use this data for training and accept the ")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                            + Text("[Terms of Service](https://mycelium.getspore.xyz/terms.html)")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                        }
                    }
                    .tint(Color(red: 0.55, green: 0.37, blue: 0.24))
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                
                Spacer()
                
                // Start training button
                Button {
                    training.startTraining()
                } label: {
                    Text("Start Training")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(training.qualityPassed && training.acceptedTerms && training.hasValidName ? Color(red: 0.55, green: 0.37, blue: 0.24) : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(!training.qualityPassed || !training.acceptedTerms || !training.hasValidName)
            }
            .padding()
        }
    }
}

private struct StatBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
            Text(label)
                .font(.caption2)
                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(red: 0.976, green: 0.965, blue: 0.949))
        .cornerRadius(8)
    }
}

// MARK: - Step 3: Training Progress

struct TrainingProgressView: View {
    @ObservedObject var training: TrainingViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color(red: 0.88, green: 0.87, blue: 0.85), lineWidth: 8)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: training.progress)
                    .stroke(Color(red: 0.55, green: 0.37, blue: 0.24), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: training.progress)
                
                Text("\(Int(training.progress * 100))%")
                    .font(.system(size: 24, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
            }
            
            // Stage info
            VStack(spacing: 8) {
                Text(training.currentStage)
                    .font(.headline)
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                Text(training.stageDetail)
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .textSelection(.enabled)
                if training.estimatedTimeRemaining > 0 {
                    Text("~\(training.estimatedTimeRemaining) min remaining")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
            }
            
            // Stage list
            VStack(alignment: .leading, spacing: 12) {
                StageRow(name: "Fetching content", done: training.progress > 0.1)
                StageRow(name: "Generating Q&A pairs", done: training.progress > 0.4)
                StageRow(name: "Training adapter", done: training.progress > 0.95)
                StageRow(name: "Converting to GGUF", done: training.progress >= 1.0)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            // Done button (when complete)
            if training.isComplete {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("Adapter ready!")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    Text("Test it out and rate responses.\nAfter 10+ ratings, you can publish to the network.")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .multilineTextAlignment(.center)
                    
                    NavigationLink {
                        TestChatView(loraHash: training.trainedLoRAHash, loraName: training.adapterName)
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                            Text("Test & Rate")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 0.55, green: 0.37, blue: 0.24))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
            }
        }
        .padding(.bottom, 32)
    }
}

private struct StageRow: View {
    let name: String
    let done: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? .green : Color(red: 0.7, green: 0.7, blue: 0.7))
                .font(.system(size: 16))
            Text(name)
                .font(.subheadline)
                .foregroundColor(done ? Color(red: 0.3, green: 0.3, blue: 0.3) : Color(red: 0.6, green: 0.6, blue: 0.6))
        }
    }
}

#endif
