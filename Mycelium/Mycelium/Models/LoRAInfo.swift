import Foundation

struct LoRAInfo: Identifiable, Codable {
    var id: String { hash }
    
    let hash: String           // BLAKE2b of adapter weights
    let name: String           // Human-readable name
    let authorPubkey: String   // Ed25519 pubkey (hex)
    let authorHandle: String   // Display name
    let baseModel: String      // e.g. "SmolLM2-1.7B-Instruct-Q4_K_M"
    let rank: Int              // LoRA rank (8, 16, 32, etc.)
    let sizeMB: Int            // Size in MB
    let tags: [String]         // e.g. ["cooking", "brazilian", "recipes"]
    let timestamp: Int64       // Unix timestamp
    let signature: String      // Ed25519 signature (hex)
    let downloadURL: String?   // HTTP URL for direct download
    let sourceURL: String?     // Link to original content source
    
    // Local-only state (not gossiped)
    var isActive: Bool = false
    var localPath: String? = nil
    var isLocal: Bool = false  // true = trained locally, not yet published to network
    
    enum CodingKeys: String, CodingKey {
        case hash, name, authorPubkey, authorHandle, baseModel, rank, sizeMB, tags, timestamp, signature, downloadURL, sourceURL, isLocal
    }
}
