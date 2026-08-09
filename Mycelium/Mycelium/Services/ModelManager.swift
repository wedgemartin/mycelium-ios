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

/// Manages the base model lifecycle: download, storage, and readiness.
class ModelManager: ObservableObject {
    @Published var state: ModelState = .needsDownload
    
    // SmolLM 1.7B Instruct Q4_K_M — good balance of size (~1GB) and quality
    static let modelURL = URL(string: "https://huggingface.co/lmstudio-community/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf")!
    static let modelFilename = "SmolLM2-1.7B-Instruct-Q4_K_M.gguf"
    
    private var downloadTask: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    
    var modelPath: String? {
        let path = modelDirectory.appendingPathComponent(Self.modelFilename).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
    
    private var modelDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    init() {
        if modelPath != nil {
            state = .ready
        }
    }
    
    func startDownload() {
        guard state != .ready else { return }
        state = .downloading(progress: 0)
        
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: Self.modelURL) { [weak self] tempURL, response, error in
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
                
                let dest = self.modelDirectory.appendingPathComponent(Self.modelFilename)
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
