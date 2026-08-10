import Foundation
import SwiftUI
import Observation

/// Manages LoRA adapter discovery, storage, and activation.
@Observable
class LoRAManager {
    var installed: [LoRAInfo] = []
    var available: [LoRAInfo] = [] // discovered from peers
    
    private let loraDirectory: URL
    private let metadataFile: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        loraDirectory = docs.appendingPathComponent("loras")
        metadataFile = docs.appendingPathComponent("loras_metadata.json")
        try? FileManager.default.createDirectory(at: loraDirectory, withIntermediateDirectories: true)
        loadMetadata()
        discoverLocalAdapters()
    }
    
    /// Path to a LoRA's GGUF file on disk
    func localPath(for lora: LoRAInfo) -> String? {
        let path = loraDirectory.appendingPathComponent("\(lora.hash).gguf").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
    
    /// Activate a LoRA adapter on the engine
    func activate(lora: LoRAInfo, engine: LlamaEngine) {
        guard let path = localPath(for: lora) else {
            print("lora: activate failed — no local file for \(lora.name) (hash=\(lora.hash))")
            return
        }
        print("lora: activating \(lora.name) from \(path)")
        engine.loadLoRA(path: path)
        if let idx = installed.firstIndex(where: { $0.hash == lora.hash }) {
            installed[idx].isActive = true
        }
        saveMetadata()
    }
    
    /// Deactivate a LoRA adapter
    func deactivate(lora: LoRAInfo, engine: LlamaEngine) {
        guard let path = localPath(for: lora) else { return }
        engine.unloadLoRA(path: path)
        if let idx = installed.firstIndex(where: { $0.hash == lora.hash }) {
            installed[idx].isActive = false
        }
        saveMetadata()
    }
    
    /// Delete a LoRA from disk
    func delete(lora: LoRAInfo, engine: LlamaEngine) {
        if lora.isActive {
            deactivate(lora: lora, engine: engine)
        }
        let path = loraDirectory.appendingPathComponent("\(lora.hash).gguf")
        try? FileManager.default.removeItem(at: path)
        installed.removeAll { $0.hash == lora.hash }
        saveMetadata()
    }
    
    /// Install a LoRA from raw data (received from peer)
    func install(lora: LoRAInfo, data: Data) {
        let path = loraDirectory.appendingPathComponent("\(lora.hash).gguf")
        do {
            try data.write(to: path)
            var info = lora
            info.localPath = path.path
            installed.append(info)
            available.removeAll { $0.hash == lora.hash }
            saveMetadata()
            print("lora: installed \(lora.name) (\(lora.sizeMB) MB)")
        } catch {
            print("lora: failed to install \(lora.name): \(error)")
        }
    }
    
    /// Register a LoRA announced by a peer (metadata only, not downloaded yet)
    func addAvailable(lora: LoRAInfo) {
        guard !installed.contains(where: { $0.hash == lora.hash }),
              !available.contains(where: { $0.hash == lora.hash }) else { return }
        available.append(lora)
    }
    
    // MARK: - Persistence
    
    /// Scan the loras/ directory for GGUF files not yet in our metadata
    private func discoverLocalAdapters() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: loraDirectory, includingPropertiesForKeys: nil) else { return }
        
        let knownHashes = Set(installed.map(\.hash))
        
        for file in files where file.pathExtension == "gguf" {
            let filename = file.deletingPathExtension().lastPathComponent
            // Skip if already registered
            if knownHashes.contains(filename) { continue }
            
            // Auto-generate metadata from filename
            let info = LoRAInfo(
                hash: filename,
                name: filename.replacingOccurrences(of: "-", with: " ").capitalized,
                authorPubkey: "local",
                authorHandle: "local",
                baseModel: "SmolLM2-1.7B-Instruct-Q4_K_M",
                rank: 8,
                sizeMB: Int((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0) ?? 0) / (1024 * 1024),
                tags: tagsFromFilename(filename),
                timestamp: Int64(Date().timeIntervalSince1970),
                signature: ""
            )
            installed.append(info)
        }
        saveMetadata()
    }
    
    private func tagsFromFilename(_ name: String) -> [String] {
        let parts = name.split(separator: "-").map(String.init)
        // First part is region, rest is topic
        if parts.count >= 2 {
            return [parts[0], parts[1...].joined(separator: " ")]
        }
        return [name]
    }
    
    private func saveMetadata() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(installed) {
            try? data.write(to: metadataFile)
        }
    }
    
    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataFile),
              let saved = try? JSONDecoder().decode([LoRAInfo].self, from: data) else { return }
        installed = saved
        // Verify files still exist
        installed = installed.filter { lora in
            let path = loraDirectory.appendingPathComponent("\(lora.hash).gguf")
            return FileManager.default.fileExists(atPath: path.path)
        }
    }
}
