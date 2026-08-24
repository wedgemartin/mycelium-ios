import Foundation
import Observation

/// Manages Mycelium's connection to the Spore network for LoRA discovery and download.
@Observable
class NetworkManager {
    var catalog: [LoRAInfo] = []
    var isConnected = false
    var isDownloading = false
    var downloadProgress: String = ""
    
    private var webSocket: URLSessionWebSocketTask?
    private var myAddress: String = ""
    private let botAddress: String
    private let derpURL: String
    private let substrateURL: String
    
    // Callbacks
    var onLoRADownloaded: ((LoRAInfo, Data) -> Void)?
    
    init() {
        // Use same infrastructure as Spore
        derpURL = "wss://derp.getspore.xyz:30882/relay"
        substrateURL = "https://ugov.xyz/api"
        botAddress = "spore16h0gj58dpjgvd99058x73e69aksk6z2wykr8ge6lzvttgme6e90qzl0yhj" // sporebot
    }
    
    func connect(address: String) {
        myAddress = address
        print("mycelium: connecting to network as \(address)")
        connectDERP()
        
        // Listen for publish requests from the training wizard
        NotificationCenter.default.addObserver(forName: .init("publishLoRA"), object: nil, queue: .main) { [weak self] notification in
            if let message = notification.userInfo?["message"] as? String {
                self?.sendRaw(message)
            }
        }
    }
    
    // MARK: - Catalog Operations
    
    /// Request LoRA catalog from the bot, optionally filtered by location/tags
    func requestCatalog(lat: Double = 0, lng: Double = 0, tags: [String] = []) {
        var request: [String: Any] = ["type": "lora_catalog_request"]
        if lat != 0 && lng != 0 {
            request["lat"] = lat
            request["lng"] = lng
        }
        if !tags.isEmpty {
            request["tags"] = tags
        }
        print("mycelium: requesting LoRA catalog from bot...")
        sendToBot(request)
    }
    
    // Chunk reassembly state
    private var pendingChunks: [String: [Int: Data]] = [:] // hash → [index → chunk data]
    private var pendingChunkTotals: [String: Int] = [:]    // hash → total expected
    
    /// Request download of a specific LoRA by hash (chunked over DERP)
    func downloadLoRA(hash: String) {
        isDownloading = true
        downloadProgress = "Requesting from network..."
        print("mycelium: requesting LoRA download for hash=\(hash)")
        
        pendingChunks[hash] = [:]
        pendingChunkTotals[hash] = 0
        
        let request: [String: Any] = [
            "type": "lora_download",
            "hash": hash
        ]
        print("mycelium: sending lora_download to bot")
        sendToBot(request)
    }
    
    /// Find LoRAs in the catalog that match extracted tags
    func matchQuery(_ query: String, extractedTags: [String] = []) -> [LoRAInfo] {
        let tags = extractedTags.isEmpty
            ? query.lowercased().split(separator: " ").map(String.init)
            : extractedTags
        
        // Normalize: remove accents for comparison
        func normalize(_ s: String) -> String {
            s.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        }
        
        let normalizedTags = tags.map { normalize($0) }
        
        return catalog.filter { lora in
            let searchable = (lora.tags + [lora.name]).map { normalize($0) }
            let matchCount = normalizedTags.filter { tag in
                searchable.contains { s in s.contains(tag) }
            }.count
            return matchCount >= 2
        }.sorted { a, b in
            let aSearchable = (a.tags + [a.name]).map { normalize($0) }
            let bSearchable = (b.tags + [b.name]).map { normalize($0) }
            let aScore = normalizedTags.filter { tag in aSearchable.contains { $0.contains(tag) } }.count
            let bScore = normalizedTags.filter { tag in bSearchable.contains { $0.contains(tag) } }.count
            return aScore > bScore
        }
    }
    
    // MARK: - DERP Connection
    
    private func connectDERP() {
        guard let url = URL(string: derpURL) else {
            print("mycelium: invalid DERP URL: \(derpURL)")
            return
        }
        print("mycelium: opening WebSocket to \(derpURL)")
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        // Register with DERP
        var frame = Data([0x01]) // frameRegister
        frame.append(myAddress.data(using: .utf8)!)
        webSocket?.send(.data(frame)) { [weak self] error in
            if let error {
                print("mycelium: DERP registration failed: \(error.localizedDescription)")
                return
            }
            self?.isConnected = true
            print("mycelium: ✅ registered with DERP as \(self?.myAddress.prefix(20) ?? "")")
            self?.receiveLoop()
            // Request catalog immediately after connecting
            self?.requestCatalog()
        }
    }
    
    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(.data(let data)):
                self?.handleFrame(data)
            case .success(.string(let text)):
                self?.handleMessage(text.data(using: .utf8) ?? Data())
            case .failure(let error):
                print("mycelium: DERP receive error: \(error.localizedDescription)")
                self?.isConnected = false
                // Reconnect after delay
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    self?.connectDERP()
                }
                return
            @unknown default:
                break
            }
            // Continue receiving
            self?.receiveLoop()
        }
    }
    
    private func handleFrame(_ data: Data) {
        // DERP frame: [0x02][4-byte sender len][sender][payload]
        guard data.count > 5, data[0] == 0x02 else { return }
        let senderLen = Int(data[1]) << 24 | Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
        guard data.count > 5 + senderLen else { return }
        let payload = data[(5 + senderLen)...]
        handleMessage(Data(payload))
    }
    
    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            print("mycelium: received non-JSON or untyped message (\(data.count) bytes)")
            return
        }
        
        print("mycelium: received message type=\(type)")
        
        switch type {
        case "lora_catalog_response":
            handleCatalogResponse(json)
        case "lora_download_response":
            handleDownloadResponse(json)
        case "lora_chunk":
            handleChunk(json)
        default:
            break
        }
    }
    
    private func handleCatalogResponse(_ json: [String: Any]) {
        guard let entries = json["entries"] as? [[String: Any]] else { return }
        
        var newCatalog: [LoRAInfo] = []
        for entry in entries {
            let info = LoRAInfo(
                hash: entry["hash"] as? String ?? "",
                name: entry["name"] as? String ?? "",
                authorPubkey: entry["author"] as? String ?? "",
                authorHandle: resolveAuthorHandle(entry["author"] as? String ?? ""),
                baseModel: entry["base_model"] as? String ?? "",
                rank: entry["rank"] as? Int ?? 8,
                sizeMB: entry["size_mb"] as? Int ?? 0,
                tags: entry["tags"] as? [String] ?? [],
                timestamp: Int64(Date().timeIntervalSince1970),
                signature: "",
                downloadURL: entry["download_url"] as? String,
                sourceURL: entry["source_url"] as? String,
                score: entry["score"] as? Int ?? 0
            )
            newCatalog.append(info)
        }
        
        DispatchQueue.main.async {
            self.catalog = newCatalog
            print("mycelium: catalog synced — \(newCatalog.count) LoRAs available")
        }
    }
    
    private func handleDownloadResponse(_ json: [String: Any]) {
        guard let hash = json["hash"] as? String,
              let binaryB64 = json["binary"] as? String,
              let data = Data(base64Encoded: binaryB64) else {
            isDownloading = false
            return
        }
        
        // Find the matching catalog entry
        if let lora = catalog.first(where: { $0.hash == hash }) {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadProgress = ""
                self.onLoRADownloaded?(lora, data)
                print("mycelium: downloaded LoRA '\(lora.name)' (\(data.count / 1024)KB)")
            }
        }
    }
    
    private func handleChunk(_ json: [String: Any]) {
        guard let hash = json["hash"] as? String,
              let index = json["index"] as? Int,
              let total = json["total"] as? Int,
              let dataB64 = json["data"] as? String,
              let chunkData = Data(base64Encoded: dataB64) else {
            print("mycelium: invalid chunk received")
            return
        }
        
        // Store chunk
        if pendingChunks[hash] == nil {
            pendingChunks[hash] = [:]
        }
        pendingChunks[hash]?[index] = chunkData
        pendingChunkTotals[hash] = total
        
        let received = pendingChunks[hash]?.count ?? 0
        print("mycelium: chunk \(index+1)/\(total) for \(hash.prefix(12)) (\(chunkData.count / 1024)KB)")
        
        DispatchQueue.main.async {
            self.downloadProgress = "Downloading... \(received)/\(total)"
        }
        
        // Check if all chunks received
        if received == total {
            // Reassemble in order
            var fullData = Data()
            for i in 0..<total {
                guard let chunk = pendingChunks[hash]?[i] else {
                    print("mycelium: missing chunk \(i) for \(hash.prefix(12))")
                    pendingChunks.removeValue(forKey: hash)
                    DispatchQueue.main.async { self.isDownloading = false }
                    return
                }
                fullData.append(chunk)
            }
            
            // Clean up
            pendingChunks.removeValue(forKey: hash)
            pendingChunkTotals.removeValue(forKey: hash)
            
            // Deliver
            if let lora = catalog.first(where: { $0.hash == hash }) {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.downloadProgress = ""
                    self.onLoRADownloaded?(lora, fullData)
                    print("mycelium: ✅ downloaded LoRA '\(lora.name)' (\(fullData.count / 1024)KB) via \(total) chunks")
                }
            }
        }
    }
    
    // MARK: - Send
    
    private func resolveAuthorHandle(_ pubkey: String) -> String {
        // Known bot address
        if pubkey.hasPrefix("spore16h0gj58dpj") { return "sporebot" }
        // Truncate unknown addresses for display
        if pubkey.hasPrefix("spore1") { return String(pubkey.dropFirst(6).prefix(8)) }
        return pubkey.prefix(12).description
    }
    
    /// Send a pre-serialized JSON message via DERP (used by training wizard publish)
    func sendRaw(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        // Extract dest and forward via DERP
        if let dest = json["dest"] as? String,
           let payload = try? JSONSerialization.data(withJSONObject: json) {
            print("mycelium: publishing LoRA to network (\(payload.count) bytes)")
            sendDERP(to: dest, payload: payload)
        }
    }
    
    /// Vote on a LoRA adapter (up or down)
    func sendVote(hash: String, vote: String) {
        let message: [String: Any] = [
            "type": "lora_vote",
            "hash": hash,
            "vote": vote
        ]
        sendToBot(message)
        print("mycelium: voted \(vote) on \(hash.prefix(12))")
    }
    
    private func sendToBot(_ message: [String: Any]) {
        guard let payload = try? JSONSerialization.data(withJSONObject: message) else {
            print("mycelium: failed to serialize message to bot")
            return
        }
        print("mycelium: sending \(message["type"] ?? "?") to bot (\(payload.count) bytes)")
        sendDERP(to: botAddress, payload: payload)
    }
    
    private func sendDERP(to dest: String, payload: Data) {
        let destData = dest.data(using: .utf8)!
        var frame = Data()
        frame.append(0x02) // frameSend
        var len = UInt32(destData.count).bigEndian
        frame.append(Data(bytes: &len, count: 4))
        frame.append(destData)
        frame.append(payload)
        webSocket?.send(.data(frame)) { error in
            if let error {
                print("mycelium: send error: \(error.localizedDescription)")
            }
        }
    }
}
