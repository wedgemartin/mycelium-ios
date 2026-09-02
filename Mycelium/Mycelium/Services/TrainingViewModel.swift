#if os(macOS)
import Foundation
import SwiftUI
import Combine
import CryptoKit

/// ViewModel for the training wizard. Handles source analysis, quality gating, and real MLX LoRA training.
class TrainingViewModel: ObservableObject {
    @Published var step: TrainingStep = .source
    
    init() {
        // Listen for retrain requests from Test & Rate
        NotificationCenter.default.addObserver(forName: .init("retrainWithFeedback"), object: nil, queue: .main) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let approved = info["approved"] as? [(String, String)],
                  let rejected = info["rejected"] as? [(String, String)] else { return }
            
            self.feedbackApproved = approved
            self.feedbackRejected = rejected
            self.startTraining() // Re-run training with curated data
        }
    }
    
    // Source input state (preserved across navigation)
    @Published var sourceType: SourceType = .rss
    @Published var rssURLInput = ""
    @Published var pastedText = ""
    
    // Source data
    @Published var sourceText = ""
    @Published var rssURL: String?
    @Published var importedFileName: String?
    @Published var isAnalyzing = false
    
    // Analysis results
    @Published var tokenCount = 0
    @Published var articleCount = 0
    @Published var estimatedQAPairs = 0
    @Published var qualityPassed = false
    @Published var qualityMessage = ""
    
    // Configuration
    @Published var adapterName = ""
    @Published var tagsString = ""
    @Published var shareToNetwork = true
    @Published var acceptedTerms = false
    
    // Training progress
    @Published var progress: Double = 0.0
    @Published var currentStage = ""
    @Published var stageDetail = ""
    @Published var estimatedTimeRemaining = 0
    @Published var isComplete = false
    @Published var trainedLoRAHash = ""
    private var trainingStartTime: Date?
    
    // Internal
    private var trainingData: [(String, String)] = []
    private var outputAdapterPath: URL?
    
    // MLX training configuration
    private let learningRate: Float = 1e-5
    private let batchSize = 1

    /// Adaptive training profile chosen from the source corpus size (token count).
    ///
    /// Rationale: LoRA capacity is set by rank × number of adapted layers. Small/dense
    /// sources (e.g. the US Constitution, a slang list) want a lean adapter to avoid
    /// overfitting; rich sources (e.g. a Wikivoyage city guide, a full book) benefit from
    /// more layers + higher rank so the model can actually absorb the knowledge.
    /// SmolLM2-1.7B has 24 transformer layers total.
    struct TrainingProfile {
        let rank: Int
        let numLayers: Int
        let iterations: Int
        let label: String
    }

    var trainingProfile: TrainingProfile {
        switch tokenCount {
        case ..<8_000:
            // Tiny/dense source — keep it lean to avoid overfitting. ~11MB.
            return TrainingProfile(rank: 8, numLayers: 6, iterations: 400, label: "compact")
        case 8_000..<40_000:
            // Medium source. ~25-35MB.
            return TrainingProfile(rank: 16, numLayers: 8, iterations: 600, label: "standard")
        default:
            // Rich source (Wikivoyage-scale, books). ~50-70MB.
            return TrainingProfile(rank: 16, numLayers: 12, iterations: 800, label: "rich")
        }
    }

    /// The MLX model to use for training (SmolLM2 in MLX format)
    private let trainingModelId = "mlx-community/SmolLM2-1.7B-Instruct-4bit"
    
    var estimatedMinutes: Int {
        max(5, (tokenCount / 1000) + 15)
    }
    
    var tags: [String] {
        tagsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }
    
    var hasValidName: Bool {
        let trimmed = adapterName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.lowercased() != "train" && !trimmed.hasPrefix("{")
    }
    
    // MARK: - File Import
    
    func importFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            sourceText = try String(contentsOf: url, encoding: .utf8)
            importedFileName = url.lastPathComponent
        } catch {
            importedFileName = nil
            sourceText = ""
        }
    }
    
    // MARK: - Analysis
    
    func analyzeSource() {
        isAnalyzing = true
        
        Task {
            if let rss = rssURL, !rss.isEmpty {
                await fetchRSS(urlString: rss)
            }
            
            await MainActor.run {
                performQualityCheck()
                isAnalyzing = false
                if qualityPassed || tokenCount > 0 {
                    step = .review
                }
            }
        }
    }
    
    private func fetchRSS(urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            let articles = parseRSSContent(text)
            
            await MainActor.run {
                sourceText = articles.joined(separator: "\n\n")
                articleCount = articles.count
            }
        } catch {
            await MainActor.run {
                qualityMessage = "Failed to fetch RSS feed: \(error.localizedDescription)"
            }
        }
    }
    
    private func parseRSSContent(_ xml: String) -> [String] {
        var articles: [String] = []
        let patterns = [
            "<content:encoded><!\\[CDATA\\[(.*?)\\]\\]></content:encoded>",
            "<description><!\\[CDATA\\[(.*?)\\]\\]></description>",
            "<description>(.*?)</description>"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
                let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: xml) {
                        let content = String(xml[range])
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if content.count > 100 {
                            articles.append(content)
                        }
                    }
                }
            }
            if !articles.isEmpty { break }
        }
        return articles
    }
    
    private func performQualityCheck() {
        tokenCount = sourceText.count / 4
        if articleCount == 0 { articleCount = 1 }
        estimatedQAPairs = max(0, (tokenCount / 500) * 3)
        
        if tokenCount < 1000 {
            qualityPassed = false
            qualityMessage = "Not enough content. Need at least ~5,000 tokens (you have ~\(tokenCount))."
        } else if estimatedQAPairs < 30 {
            qualityPassed = false
            qualityMessage = "Content is too thin — would only generate ~\(estimatedQAPairs) Q&A pairs (need 30+)."
        } else if checkRepetitive() {
            qualityPassed = false
            qualityMessage = "Content is too repetitive to produce a useful adapter."
        } else {
            qualityPassed = true
            qualityMessage = "Good to go! Enough content for a quality adapter."
        }
        
        if adapterName.isEmpty { adapterName = suggestName() }
    }
    
    private func checkRepetitive() -> Bool {
        let words = sourceText.lowercased().split(separator: " ")
        guard words.count > 50 else { return false }
        var trigrams = Set<String>()
        for i in 0..<(words.count - 2) {
            trigrams.insert("\(words[i]) \(words[i+1]) \(words[i+2])")
        }
        return Double(trigrams.count) / Double(words.count) < 0.3
    }
    
    private func suggestName() -> String {
        if let rss = rssURL, let host = URL(string: rss)?.host {
            return host.replacingOccurrences(of: "www.", with: "")
                .replacingOccurrences(of: ".com", with: "")
                .replacingOccurrences(of: ".org", with: "")
                .capitalized
        }
        // If source looks like JSON/JSONL, use filename instead
        if sourceText.hasPrefix("{") || sourceText.hasPrefix("[") {
            if let fileName = importedFileName {
                return fileName.replacingOccurrences(of: ".jsonl", with: "")
                    .replacingOccurrences(of: ".json", with: "")
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
            }
            return "Custom Adapter"
        }
        let words = sourceText.prefix(200).split(separator: " ").prefix(4)
        return words.joined(separator: " ") + "..."
    }
    
    // MARK: - Training
    
    func startTraining() {
        step = .training
        progress = 0.0
        isComplete = false
        trainingStartTime = Date()
        
        Task {
            do {
                // Stage 1: Generate Q&A pairs
                await MainActor.run {
                    currentStage = "Generating Q&A pairs"
                    stageDetail = "Creating training data from your content..."
                    estimatedTimeRemaining = estimatedMinutes
                }
                await generateQAPairs()
                
                // Stage 2: MLX LoRA Training
                await MainActor.run {
                    currentStage = "Training adapter"
                    stageDetail = "Loading model..."
                    estimatedTimeRemaining = max(1, estimatedMinutes - 5)
                }
                try await trainLoRA()
                
                // Stage 3: Convert to GGUF
                await MainActor.run {
                    currentStage = "Converting to GGUF"
                    stageDetail = "Packaging adapter for inference..."
                    progress = 0.95
                    estimatedTimeRemaining = 0
                }
                try await convertToGGUF()
                
                // Install locally for testing (don't publish yet)
                await installLocalAdapter()
                
                await MainActor.run {
                    progress = 1.0
                    currentStage = "Complete"
                    stageDetail = "Adapter installed! Try it out, then publish from your Library."
                    isComplete = true
                }
            } catch {
                await MainActor.run {
                    currentStage = "Failed"
                    stageDetail = "Training failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func generateQAPairs() async {
        let paragraphs = sourceText.components(separatedBy: "\n\n").filter { $0.count > 100 }
        
        await MainActor.run {
            stageDetail = "Generating Q&A pairs using AI..."
            progress = 0.12
        }
        
        // Use Python + mlx_lm to generate intelligent Q&A pairs from the source text
        do {
            let pythonPath = try await ensurePythonEnvironment()
            
            // Write source text to temp file
            let sourceFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("source_\(UUID().uuidString).txt")
            try sourceText.write(to: sourceFile, atomically: true, encoding: .utf8)
            
            let outputFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("qa_output_\(UUID().uuidString).jsonl")
            
            let qaScript = """
            import json, sys, os
            import resource
            original_setrlimit = resource.setrlimit
            def patched_setrlimit(*args, **kwargs):
                try:
                    original_setrlimit(*args, **kwargs)
                except (ValueError, OSError):
                    pass
            resource.setrlimit = patched_setrlimit
            
            from mlx_lm import load, generate
            
            # Read source text
            with open("\(sourceFile.path)") as f:
                text = f.read()
            
            # Load the model for Q&A generation
            print("QA_STATUS:Loading model for Q&A generation...", flush=True)
            model, tokenizer = load("mlx-community/SmolLM2-1.7B-Instruct")
            
            # Split into paragraphs
            paragraphs = [p.strip() for p in text.split("\\n\\n") if len(p.strip()) > 100]
            
            qa_pairs = []
            for i, para in enumerate(paragraphs):
                trimmed = para[:500]
                
                # Use the model to generate natural questions about this content
                prompt = tokenizer.apply_chat_template([
                    {"role": "system", "content": "Generate exactly 3 diverse questions that a user might ask about the following content. Output only the questions, one per line, no numbering."},
                    {"role": "user", "content": trimmed}
                ], tokenize=False, add_generation_prompt=True)
                
                response = generate(model, tokenizer, prompt=prompt, max_tokens=150)
                
                # Parse questions from response
                questions = [q.strip() for q in response.strip().split("\\n") if q.strip() and len(q.strip()) > 10][:3]
                
                # If model didn't generate good questions, fall back to templates
                if len(questions) < 2:
                    first_sentence = trimmed.split(".")[0] if "." in trimmed else trimmed[:80]
                    questions = [
                        f"What is this about: {first_sentence}?",
                        f"Tell me about {first_sentence[:60]}",
                        f"What do you know about {first_sentence[:50]}?"
                    ]
                
                # Create Q&A pairs with the content as the answer
                for q in questions:
                    qa_pairs.append({"messages": [
                        {"role": "user", "content": q},
                        {"role": "assistant", "content": trimmed}
                    ]})
                
                # Progress
                print(f"QA_PROGRESS:{len(qa_pairs)}/{len(paragraphs)*3}", flush=True)
            
            # Write output
            with open("\(outputFile.path)", "w") as f:
                for pair in qa_pairs:
                    f.write(json.dumps(pair) + "\\n")
            
            print(f"QA_COMPLETE:{len(qa_pairs)}")
            """
            
            let scriptFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("gen_qa.py")
            try qaScript.write(to: scriptFile, atomically: true, encoding: .utf8)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [scriptFile.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            
            // Monitor progress
            let handle = pipe.fileHandleForReading
            Task {
                for try await line in handle.bytes.lines {
                    if line.hasPrefix("QA_PROGRESS:") {
                        let parts = line.replacingOccurrences(of: "QA_PROGRESS:", with: "").split(separator: "/")
                        if let current = Int(parts.first ?? ""), let total = Int(parts.last ?? "") {
                            await MainActor.run {
                                self.progress = 0.1 + (Double(current) / Double(total)) * 0.3
                                self.stageDetail = "Generated \(current)/\(total) Q&A pairs..."
                            }
                        }
                    }
                }
            }
            
            process.waitUntilExit()
            
            // Read generated Q&A pairs back
            if FileManager.default.fileExists(atPath: outputFile.path) {
                let content = try String(contentsOf: outputFile, encoding: .utf8)
                let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
                var pairs: [(String, String)] = []
                for line in lines {
                    if let data = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let messages = json["messages"] as? [[String: String]],
                       messages.count == 2 {
                        pairs.append((messages[0]["content"] ?? "", messages[1]["content"] ?? ""))
                    }
                }
                await MainActor.run {
                    self.trainingData = pairs
                    self.estimatedQAPairs = pairs.count
                    self.stageDetail = "Generated \(pairs.count) Q&A pairs"
                }
            }
            
            // Cleanup temp files
            try? FileManager.default.removeItem(at: sourceFile)
            try? FileManager.default.removeItem(at: scriptFile)
            
        } catch {
            // Fallback to mechanical generation if Python fails
            var qaPairs: [(String, String)] = []
            for paragraph in paragraphs {
                let trimmed = String(paragraph.prefix(500))
                let firstSentence = trimmed.components(separatedBy: ".").first ?? String(trimmed.prefix(80))
                qaPairs.append(("What is this about: \(firstSentence)?", trimmed))
                qaPairs.append(("Tell me about \(String(firstSentence.prefix(60)))", trimmed))
                qaPairs.append(("What do you know about \(String(firstSentence.prefix(50)))?", trimmed))
            }
            await MainActor.run {
                self.trainingData = qaPairs
                self.estimatedQAPairs = qaPairs.count
            }
        }
    }
    
    private func trainLoRA() async throws {
        // Train LoRA using Python mlx_lm under the hood
        // This uses the same pipeline as our server-side training but runs locally
        
        await MainActor.run {
            stageDetail = "Preparing Python environment..."
            progress = 0.42
        }
        
        // Ensure Python + mlx-lm are available
        let pythonPath = try await ensurePythonEnvironment()
        
        // Prepare training data as JSONL
        let trainURL = prepareTrainingJSONL()
        guard let trainURL else {
            throw TrainingError.dataPreparation("Failed to write training data")
        }
        
        // Split into train/valid files
        let (trainFile, validFile) = try splitTrainValid(source: trainURL)
        
        await MainActor.run {
            stageDetail = "Training with MLX LoRA..."
            progress = 0.45
        }
        
        // Output directory for adapter weights
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lora_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        // Run mlx_lm.lora training
        let trainScript = """
        import resource, sys
        # Fix resource limit issue in sandboxed environments
        original_setrlimit = resource.setrlimit
        def patched_setrlimit(*args, **kwargs):
            try:
                original_setrlimit(*args, **kwargs)
            except (ValueError, OSError):
                pass
        resource.setrlimit = patched_setrlimit
        
        from types import SimpleNamespace
        from mlx_lm.lora import run
        
        args = SimpleNamespace(
            model="mlx-community/SmolLM2-1.7B-Instruct",
            train=True,
            fine_tune_type="lora",
            optimizer="adam",
            optimizer_config={"adam": {}, "adamw": {}, "muon": {}, "sgd": {}, "adafactor": {}},
            data="\(trainFile.deletingLastPathComponent().path)",
            seed=0,
            num_layers=\(trainingProfile.numLayers),
            batch_size=\(batchSize),
            iters=\(trainingProfile.iterations),
            val_batches=25,
            learning_rate=\(learningRate),
            steps_per_report=10,
            steps_per_eval=50,
            resume_adapter_file=None,
            adapter_path="\(outputDir.path)",
            save_every=100,
            test=False,
            test_batches=500,
            max_seq_length=2048,
            config=None,
            grad_checkpoint=False,
            grad_accumulation_steps=1,
            clear_cache_threshold=0,
            lr_schedule=None,
            lora_parameters={"rank": \(trainingProfile.rank), "dropout": 0.0, "scale": 20.0},
            mask_prompt=False,
            report_to=None,
            project_name=None
        )
        
        run(args)
        print("TRAINING_COMPLETE")
        """
        
        let scriptFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("train_lora.py")
        try trainScript.write(to: scriptFile, atomically: true, encoding: .utf8)
        
        // Execute Python training with progress monitoring
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptFile.path]
        process.currentDirectoryURL = outputDir
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        // Monitor output for progress
        let handle = pipe.fileHandleForReading
        var iterationsSeen = 0
        
        Task {
            for try await line in handle.bytes.lines {
                if line.contains("Iter") {
                    iterationsSeen += 10
                    await MainActor.run {
                        let totalIters = self.trainingProfile.iterations
                        self.progress = min(0.93, 0.45 + (Double(iterationsSeen) / Double(totalIters)) * 0.48)
                        self.stageDetail = "Iteration \(min(iterationsSeen, totalIters))/\(totalIters)"
                        self.estimatedTimeRemaining = max(0, (totalIters - iterationsSeen) / 20)
                    }
                }
                if line.contains("Val loss") {
                    await MainActor.run {
                        self.stageDetail = line.trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        
        // Wait for process on a background thread to avoid blocking cooperative pool
        let exitStatus = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
        
        guard exitStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw TrainingError.training("Python training failed:\n\(errorOutput.suffix(500))")
        }
        
        outputAdapterPath = outputDir
        
        await MainActor.run {
            stageDetail = "Adapter weights saved"
            progress = 0.93
        }
    }
    
    /// Ensure a dedicated Python venv with mlx-lm is available
    private func ensurePythonEnvironment() async throws -> String {
        // Find system python3
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        
        var systemPython: String?
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                systemPython = candidate
                break
            }
        }
        
        guard let python = systemPython else {
            throw TrainingError.training("Python 3 not found. Install with: brew install python3")
        }
        
        // Create a dedicated venv for Mycelium training
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let venvDir = appSupport.appendingPathComponent("Mycelium/training-venv")
        let venvPython = venvDir.appendingPathComponent("bin/python3").path
        
        if !FileManager.default.fileExists(atPath: venvPython) {
            // Create venv
            await MainActor.run {
                self.stageDetail = "Setting up Python environment (first time)..."
            }
            
            try FileManager.default.createDirectory(at: venvDir.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            
            let createVenv = Process()
            createVenv.executableURL = URL(fileURLWithPath: python)
            createVenv.arguments = ["-m", "venv", venvDir.path]
            createVenv.standardOutput = FileHandle.nullDevice
            createVenv.standardError = FileHandle.nullDevice
            
            try createVenv.run()
            createVenv.waitUntilExit()
            
            guard createVenv.terminationStatus == 0 else {
                throw TrainingError.training("Failed to create Python venv")
            }
        }
        
        // Check if mlx-lm is installed in the venv
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: venvPython)
        checkProcess.arguments = ["-c", "import mlx_lm"]
        checkProcess.standardOutput = FileHandle.nullDevice
        checkProcess.standardError = FileHandle.nullDevice
        
        try checkProcess.run()
        checkProcess.waitUntilExit()
        
        if checkProcess.terminationStatus != 0 {
            // Install mlx-lm into the venv
            await MainActor.run {
                self.stageDetail = "Installing mlx-lm (first time, may take a minute)..."
            }
            
            let pipInstall = Process()
            pipInstall.executableURL = URL(fileURLWithPath: venvPython)
            pipInstall.arguments = ["-m", "pip", "install", "--upgrade", "pip"]
            pipInstall.standardOutput = FileHandle.nullDevice
            pipInstall.standardError = FileHandle.nullDevice
            try pipInstall.run()
            pipInstall.waitUntilExit()
            
            let installMLX = Process()
            installMLX.executableURL = URL(fileURLWithPath: venvPython)
            installMLX.arguments = ["-m", "pip", "install", "mlx-lm"]
            let installPipe = Pipe()
            installMLX.standardOutput = installPipe
            installMLX.standardError = installPipe
            
            try installMLX.run()
            installMLX.waitUntilExit()
            
            guard installMLX.terminationStatus == 0 else {
                let errorOutput = String(data: installPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                // Clean up failed venv so it retries next time
                try? FileManager.default.removeItem(at: venvDir)
                throw TrainingError.training("Failed to install mlx-lm:\n\(errorOutput.suffix(500))")
            }
        }
        
        return venvPython
    }
    
    /// Split JSONL into 90% train / 10% valid
    private func splitTrainValid(source: URL) throws -> (URL, URL) {
        let content = try String(contentsOf: source, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        let splitIndex = Int(Double(lines.count) * 0.9)
        let trainLines = Array(lines.prefix(splitIndex))
        let validLines = Array(lines.suffix(from: splitIndex))
        
        let dir = source.deletingLastPathComponent()
        let trainFile = dir.appendingPathComponent("train.jsonl")
        let validFile = dir.appendingPathComponent("valid.jsonl")
        
        try trainLines.joined(separator: "\n").write(to: trainFile, atomically: true, encoding: .utf8)
        try validLines.joined(separator: "\n").write(to: validFile, atomically: true, encoding: .utf8)
        
        return (trainFile, validFile)
    }
    
    /// Feedback data for retraining (from Test & Rate)
    private var feedbackApproved: [(String, String)] = []
    private var feedbackRejected: [(String, String)] = []
    
    private func prepareTrainingJSONL() -> URL? {
        guard !trainingData.isEmpty || !feedbackApproved.isEmpty else { return nil }
        
        let tempDir = FileManager.default.temporaryDirectory
        let trainFile = tempDir.appendingPathComponent("mycelium_train_\(UUID().uuidString).jsonl")
        
        var jsonl = ""
        
        // Original training data (exclude any that match rejected feedback)
        let rejectedSet = Set(feedbackRejected.map { "\($0.0)|\($0.1)" })
        for (question, answer) in trainingData {
            let key = "\(question)|\(answer)"
            if rejectedSet.contains(key) { continue } // Skip rejected pairs
            
            let entry: [String: Any] = [
                "messages": [
                    ["role": "user", "content": question],
                    ["role": "assistant", "content": answer]
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: entry),
               let line = String(data: data, encoding: .utf8) {
                jsonl += line + "\n"
            }
        }
        
        // Add approved feedback as additional training examples
        for (question, answer) in feedbackApproved {
            let entry: [String: Any] = [
                "messages": [
                    ["role": "user", "content": question],
                    ["role": "assistant", "content": answer]
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: entry),
               let line = String(data: data, encoding: .utf8) {
                jsonl += line + "\n"
            }
        }
        
        try? jsonl.write(to: trainFile, atomically: true, encoding: .utf8)
        
        try? jsonl.write(to: trainFile, atomically: true, encoding: .utf8)
        return trainFile
    }
    
    private func convertToGGUF() async throws {
        // Convert MLX LoRA weights (safetensors) → GGUF using Python
        // The mlx_lm output is in safetensors format, we use llama.cpp's converter
        
        guard let adapterDir = outputAdapterPath else {
            throw TrainingError.conversion("No adapter weights found")
        }
        
        await MainActor.run {
            stageDetail = "Converting to GGUF format..."
            progress = 0.96
        }
        
        let pythonPath = try await ensurePythonEnvironment()
        
        let convertScript = """
        import resource, sys, os, struct
        original_setrlimit = resource.setrlimit
        def patched_setrlimit(*args, **kwargs):
            try:
                original_setrlimit(*args, **kwargs)
            except (ValueError, OSError):
                pass
        resource.setrlimit = patched_setrlimit
        
        import numpy as np
        from safetensors.numpy import load_file
        
        adapter_dir = "\(adapterDir.path)"
        adapter_file = os.path.join(adapter_dir, "adapters.safetensors")
        output_file = os.path.join(adapter_dir, "\(sanitizedName()).gguf")
        
        # Load safetensors
        tensors = load_file(adapter_file)
        
        # Convert keys from MLX format to llama.cpp GGUF format
        gguf_tensors = {}
        for key, tensor in tensors.items():
            # MLX format: model.layers.N.self_attn.X_proj.lora_a
            # or: model.layers.N.mlp.X_proj.lora_a
            # GGUF format: blk.N.attn_q.weight.loraA
            new_key = key
            new_key = new_key.replace("model.layers.", "blk.")
            new_key = new_key.replace("self_attn.q_proj", "attn_q")
            new_key = new_key.replace("self_attn.k_proj", "attn_k")
            new_key = new_key.replace("self_attn.v_proj", "attn_v")
            new_key = new_key.replace("self_attn.o_proj", "attn_output")
            new_key = new_key.replace("mlp.gate_proj", "ffn_gate")
            new_key = new_key.replace("mlp.up_proj", "ffn_up")
            new_key = new_key.replace("mlp.down_proj", "ffn_down")
            new_key = new_key.replace(".lora_a", ".weight.loraA")
            new_key = new_key.replace(".lora_b", ".weight.loraB")
            
            arr = tensor.astype(np.float16)
            if "loraB" in new_key:
                arr = arr.T  # Transpose B matrix
            gguf_tensors[new_key] = arr
        
        # Write minimal GGUF
        with open(output_file, "wb") as f:
            # Header
            f.write(b"GGUF")
            f.write(struct.pack("<I", 3))  # version
            f.write(struct.pack("<Q", len(gguf_tensors)))  # tensor count
            f.write(struct.pack("<Q", 1))  # metadata count
            
            # Metadata: general.architecture
            arch = "llama"
            f.write(struct.pack("<Q", len("general.architecture")))
            f.write(b"general.architecture")
            f.write(struct.pack("<I", 8))  # STRING type
            f.write(struct.pack("<Q", len(arch)))
            f.write(arch.encode())
            
            # Tensor headers
            offset = 0
            tensor_data_list = []
            for name, arr in sorted(gguf_tensors.items()):
                name_bytes = name.encode()
                f.write(struct.pack("<Q", len(name_bytes)))
                f.write(name_bytes)
                f.write(struct.pack("<I", len(arr.shape)))
                for dim in arr.shape:
                    f.write(struct.pack("<Q", dim))
                f.write(struct.pack("<I", 1))  # F16
                f.write(struct.pack("<Q", offset))
                data = arr.tobytes()
                tensor_data_list.append(data)
                offset += len(data)
            
            # Alignment
            pos = f.tell()
            pad = (32 - (pos % 32)) % 32
            f.write(b"\\x00" * pad)
            
            # Tensor data
            for data in tensor_data_list:
                f.write(data)
        
        print(f"GGUF written: {output_file}")
        print("CONVERSION_COMPLETE")
        """
        
        let scriptFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("convert_gguf.py")
        try convertScript.write(to: scriptFile, atomically: true, encoding: .utf8)
        
        let convertProcess = Process()
        convertProcess.executableURL = URL(fileURLWithPath: pythonPath)
        convertProcess.arguments = [scriptFile.path]
        let convertPipe = Pipe()
        convertProcess.standardOutput = convertPipe
        convertProcess.standardError = convertPipe
        
        try convertProcess.run()
        convertProcess.waitUntilExit()
        
        guard convertProcess.terminationStatus == 0 else {
            let errorOutput = String(data: convertPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
            throw TrainingError.conversion("GGUF conversion failed:\n\(errorOutput.suffix(500))")
        }
        
        await MainActor.run {
            stageDetail = "Adapter ready: \(self.sanitizedName()).gguf"
            progress = 0.99
        }
    }
    
    /// Install the trained adapter locally for testing before publishing
    /// Report a metadata-only activation event to the substrate, which forwards a summary
    /// to Slack. No training data, source content, or user identity is sent — only the
    /// adapter name, base model, source type, size, and (for training) duration.
    private func reportEvent(type: String, sizeMB: Int, hash: String = "") {
        guard let url = URL(string: "https://substrate.getspore.xyz:30880/mycelium/event") else { return }
        var duration = 0
        if let start = trainingStartTime {
            duration = Int(Date().timeIntervalSince(start))
        }
        let body: [String: Any] = [
            "type": type,
            "name": adapterName,
            "base_model": "SmolLM2-1.7B-Instruct",
            "source": sourceType.rawValue,
            "size_mb": sizeMB,
            "duration_sec": duration,
            "hash": hash
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10
        // Fire-and-forget — never block or fail the training/publish flow on this.
        URLSession.shared.dataTask(with: req).resume()
    }

    private func installLocalAdapter() async {
        guard let adapterDir = outputAdapterPath else { return }
        
        let ggufFile = adapterDir.appendingPathComponent("\(sanitizedName()).gguf")
        guard FileManager.default.fileExists(atPath: ggufFile.path) else { return }
        
        // Copy to the LoRA directory
        let loraDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("loras")
        try? FileManager.default.createDirectory(at: loraDir, withIntermediateDirectories: true)
        
        // Compute hash for filename
        let data = try? Data(contentsOf: ggufFile)
        guard let data else { return }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16)
        let destFile = loraDir.appendingPathComponent("\(hash).gguf")
        
        try? FileManager.default.copyItem(at: ggufFile, to: destFile)
        
        // Store hash for test chat
        await MainActor.run {
            trainedLoRAHash = String(hash)
        }

        // Report the training activation event (metadata only) to Slack via substrate.
        reportEvent(type: "trained", sizeMB: data.count / (1024 * 1024), hash: String(hash))
        
        // Notify the app to pick up the new adapter
        await MainActor.run {
            NotificationCenter.default.post(
                name: .init("loraTrainedLocally"),
                object: nil,
                userInfo: [
                    "hash": String(hash),
                    "name": adapterName,
                    "tags": tags,
                    "path": destFile.path,
                    "isLocal": true
                ]
            )
        }
    }
    
    /// Publish the trained adapter to the Spore network via DERP
    private func publishToNetwork() async throws {
        guard let adapterDir = outputAdapterPath else {
            throw TrainingError.conversion("No adapter to publish")
        }
        
        // Find the GGUF file
        let ggufFile = adapterDir.appendingPathComponent("\(sanitizedName()).gguf")
        guard FileManager.default.fileExists(atPath: ggufFile.path) else {
            throw TrainingError.conversion("GGUF file not found for publishing")
        }
        
        let binaryData = try Data(contentsOf: ggufFile)
        
        // Compute BLAKE2b hash (using SHA256 as fallback since we don't have BLAKE2b in Swift stdlib)
        let hashData = binaryData.withUnsafeBytes { bytes in
            var hasher = SHA256()
            hasher.update(bufferPointer: UnsafeRawBufferPointer(bytes))
            return hasher.finalize()
        }
        let hash = hashData.map { String(format: "%02x", $0) }.joined()
        
        // Base64 encode the binary
        let binaryB64 = binaryData.base64EncodedString()
        
        // Build the publish message
        let publishPayload: [String: Any] = [
            "hash": hash,
            "name": adapterName,
            "tags": tags,
            "base_model": "SmolLM2-1.7B-Instruct-Q4_K_M",
            "rank": trainingProfile.rank,
            "size_mb": binaryData.count / (1024 * 1024),
            "source_url": (sourceType == .rss ? (rssURL ?? "") : ""),
            "lat": 0.0,  // TODO: get user location
            "lng": 0.0,
            "binary": binaryB64
        ]
        
        let message: [String: Any] = [
            "type": "lora_publish",
            "dest": "spore16h0gj58dpjgvd99058x73e69aksk6z2wykr8ge6lzvttgme6e90qzl0yhj",
            "payload": publishPayload
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw TrainingError.conversion("Failed to serialize publish message")
        }
        
        // Send via the NetworkManager's DERP connection
        await MainActor.run {
            // Access the network manager to send
            // Note: In production, inject NetworkManager properly
            NotificationCenter.default.post(
                name: .init("publishLoRA"),
                object: nil,
                userInfo: ["message": jsonString]
            )
            stageDetail = "Published to network! (\(binaryData.count / 1024)KB)"
        }

        // Report the publish activation event (metadata only) to Slack via substrate.
        reportEvent(type: "published", sizeMB: binaryData.count / (1024 * 1024), hash: hash)
    }
    
    private func loraOutputDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("trained_loras")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func sanitizedName() -> String {
        adapterName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_-]", with: "", options: .regularExpression)
    }
}

enum TrainingError: Error, LocalizedError {
    case dataPreparation(String)
    case conversion(String)
    case training(String)
    
    var errorDescription: String? {
        switch self {
        case .dataPreparation(let msg): return msg
        case .conversion(let msg): return msg
        case .training(let msg): return msg
        }
    }
}

#endif
