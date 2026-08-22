import Foundation
import Combine
import SwiftUI

enum ModelState: Equatable {
    case needsDownload
    case downloading(progress: Double)
    case ready
    case error(String)
    
    static func == (lhs: ModelState, rhs: ModelState) -> Bool {
        switch (lhs, rhs) {
        case (.needsDownload, .needsDownload): return true
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.ready, .ready): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

/// Available models with their specifications.
struct ModelOption: Identifiable {
    let id: String
    let name: String
    let filename: String
    let url: URL
    let sizeMB: Int
    let minRAMGB: Int
    let description: String
    let nGpuLayers: Int
}

/// Manages the base model lifecycle: selection, download, storage, and readiness.
class ModelManager: ObservableObject {
    @Published var state: ModelState = .needsDownload
    @Published var selectedModel: ModelOption
    
    static let models: [ModelOption] = [
        ModelOption(
            id: "smollm2-360m",
            name: "SmolLM2 360M",
            filename: "SmolLM2-360M-Instruct-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/lmstudio-community/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf")!,
            sizeMB: 250,
            minRAMGB: 3,
            description: "Fastest, fits any device. Basic quality.",
            nGpuLayers: 99
        ),
        ModelOption(
            id: "smollm2-1.7b",
            name: "SmolLM2 1.7B",
            filename: "SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/lmstudio-community/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf")!,
            sizeMB: 1000,
            minRAMGB: 4,
            description: "Good balance of speed and quality.",
            nGpuLayers: 99
        ),
        ModelOption(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/lmstudio-community/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            sizeMB: 2000,
            minRAMGB: 6,
            description: "High quality. Requires iPhone 15 Pro+.",
            nGpuLayers: 99
        ),
        ModelOption(
            id: "llama-3.1-8b",
            name: "Llama 3.1 8B",
            filename: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf")!,
            sizeMB: 5500,
            minRAMGB: 10,
            description: "Best quality. For Mac training & inference.",
            nGpuLayers: 99
        ),
    ]
    
    /// Device RAM in GB
    static var deviceRAMGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }
    
    /// Models appropriate for this device
    static var availableModels: [ModelOption] {
        #if os(macOS)
        // Mac shows only SmolLM2 models (for LoRA compatibility with phones)
        return models.filter { $0.id.hasPrefix("smollm2") }
        #else
        return models.filter { $0.minRAMGB <= deviceRAMGB }
        #endif
    }
    
    /// Best model for this device
    static var recommendedModel: ModelOption {
        #if os(macOS)
        // Mac uses same model as phones for LoRA compatibility
        return models.first { $0.id == "smollm2-1.7b" }!
        #else
        // iOS: recommend the largest that fits in device RAM
        let ram = deviceRAMGB
        if ram >= 6 {
            return models.first { $0.id == "llama-3.2-3b" }!
        } else if ram >= 4 {
            return models.first { $0.id == "smollm2-1.7b" }!
        } else {
            return models.first { $0.id == "smollm2-360m" }!
        }
        #endif
    }
    
    private var downloadTask: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    
    var modelPath: String? {
        let path = modelDirectory.appendingPathComponent(selectedModel.filename).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
    
    var nGpuLayers: Int {
        #if targetEnvironment(simulator)
        return 0
        #else
        return selectedModel.nGpuLayers
        #endif
    }
    
    private var modelDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    init() {
        // Check if user previously selected a model
        if let savedId = UserDefaults.standard.string(forKey: "selected_model_id"),
           let saved = Self.models.first(where: { $0.id == savedId }) {
            self.selectedModel = saved
        } else {
            self.selectedModel = Self.recommendedModel
        }
        
        if modelPath != nil {
            state = .ready
        }
    }
    
    func selectModel(_ model: ModelOption) {
        selectedModel = model
        UserDefaults.standard.set(model.id, forKey: "selected_model_id")
        // Check if this model is already downloaded
        let path = modelDirectory.appendingPathComponent(model.filename).path
        if FileManager.default.fileExists(atPath: path) {
            state = .ready
        } else {
            state = .needsDownload
        }
    }
    
    func startDownload() {
        guard state != .ready else { return }
        state = .downloading(progress: 0)
        
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: selectedModel.url) { [weak self] tempURL, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.state = .error(error.localizedDescription)
                    return
                }
                guard let tempURL else {
                    self.state = .error("Download failed — no file received")
                    return
                }
                
                let dest = self.modelDirectory.appendingPathComponent(self.selectedModel.filename)
                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    self.state = .ready
                } catch {
                    self.state = .error("Failed to save model: \(error.localizedDescription)")
                }
            }
        }
        
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }
        
        task.resume()
        downloadTask = task
    }
    
    func retryDownload() {
        state = .needsDownload
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        state = .needsDownload
    }
}
