import Foundation
import Network
import Observation

/// Handles local peer discovery and direct P2P LoRA transfer between Mycelium devices.
@Observable
class PeerManager {
    var discoveredPeers: [Peer] = []
    var isAdvertising = false
    
    struct Peer: Identifiable {
        let id: String // address
        let host: String
        let port: UInt16
        var availableLoRAs: [String] = [] // hashes this peer has
    }
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let serviceType = "_mycelium._udp"
    private let port: UInt16 = 9010
    private var myAddress: String = ""
    private var myLoRAHashes: [String] = [] // what we have locally
    
    // Callback when a LoRA is received from a peer
    var onLoRAReceived: ((String, Data) -> Void)? // (hash, data)
    
    func start(address: String, installedHashes: [String]) {
        myAddress = address
        myLoRAHashes = installedHashes
        startAdvertising()
        startBrowsing()
    }
    
    func updateHashes(_ hashes: [String]) {
        myLoRAHashes = hashes
    }
    
    /// Request a LoRA from a peer that has it
    func requestLoRA(hash: String, from peer: Peer) {
        print("p2p: requesting LoRA \(hash.prefix(12)) from \(peer.host)")
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(peer.host), port: NWEndpoint.Port(rawValue: peer.port)!)
        let connection = NWConnection(to: endpoint, using: .udp)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Send request: "LORA_REQ:<hash>"
                let request = "LORA_REQ:\(hash)".data(using: .utf8)!
                connection.send(content: request, completion: .contentProcessed { _ in })
                
                // Receive the response (chunked binary)
                self?.receiveLoRA(connection: connection, hash: hash)
            case .failed(let error):
                print("p2p: connection to \(peer.host) failed: \(error)")
            default:
                break
            }
        }
        connection.start(queue: .global())
    }
    
    /// Check if any discovered peer has a given LoRA hash
    func peerWith(loraHash: String) -> Peer? {
        discoveredPeers.first { $0.availableLoRAs.contains(loraHash) }
    }
    
    // MARK: - Advertising (so other peers can find us)
    
    private func startAdvertising() {
        do {
            let params = NWParameters.udp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.service = NWListener.Service(
                name: myAddress.prefix(20).description,
                type: serviceType
            )
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncoming(connection)
            }
            
            listener?.stateUpdateHandler = { state in
                if case .ready = state {
                    print("p2p: advertising on port \(self.port)")
                }
            }
            
            listener?.start(queue: .global())
            isAdvertising = true
        } catch {
            print("p2p: failed to start listener: \(error)")
        }
    }
    
    // MARK: - Browsing (find other Mycelium peers)
    
    private func startBrowsing() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true
        
        browser = NWBrowser(for: descriptor, using: params)
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                self?.handleDiscovery(result)
            }
        }
        
        browser?.start(queue: .global())
        print("p2p: browsing for peers...")
    }
    
    private func handleDiscovery(_ result: NWBrowser.Result) {
        // Extract peer address from the service name
        guard case .service(let name, _, _, _) = result.endpoint else { return }
        
        // Don't connect to ourselves
        if name == myAddress.prefix(20).description { return }
        
        // Resolve and connect to ask what LoRAs they have
        let connection = NWConnection(to: result.endpoint, using: .udp)
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                // Ask peer what LoRAs they have: "LORA_LIST?"
                let request = "LORA_LIST?".data(using: .utf8)!
                connection.send(content: request, completion: .contentProcessed { _ in })
                
                // Receive their list
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                    guard let data, let response = String(data: data, encoding: .utf8) else { return }
                    // Response format: "LORA_LIST:<hash1>,<hash2>,..."
                    if response.hasPrefix("LORA_LIST:") {
                        let hashStr = String(response.dropFirst("LORA_LIST:".count))
                        let hashes = hashStr.split(separator: ",").map(String.init)
                        
                        // Get the resolved host
                        if let path = connection.currentPath,
                           let endpoint = path.remoteEndpoint,
                           case .hostPort(let host, let port) = endpoint {
                            let peer = Peer(
                                id: name,
                                host: "\(host)",
                                port: port.rawValue,
                                availableLoRAs: hashes
                            )
                            DispatchQueue.main.async {
                                if !(self?.discoveredPeers.contains(where: { $0.id == name }) ?? false) {
                                    self?.discoveredPeers.append(peer)
                                    print("p2p: discovered peer \(name) with \(hashes.count) LoRAs")
                                }
                            }
                        }
                    }
                    connection.cancel()
                }
            }
        }
        connection.start(queue: .global())
    }
    
    // MARK: - Incoming requests
    
    private func handleIncoming(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
                    guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
                    
                    if request == "LORA_LIST?" {
                        // Respond with our available LoRA hashes
                        let response = "LORA_LIST:" + self.myLoRAHashes.joined(separator: ",")
                        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    } else if request.hasPrefix("LORA_REQ:") {
                        // Peer is requesting a specific LoRA binary
                        let hash = String(request.dropFirst("LORA_REQ:".count))
                        self.serveLoRA(hash: hash, to: connection)
                    }
                }
            }
        }
        connection.start(queue: .global())
    }
    
    private func serveLoRA(hash: String, to connection: NWConnection) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let loraPath = docs.appendingPathComponent("loras/\(hash).gguf")
        
        guard let data = try? Data(contentsOf: loraPath) else {
            print("p2p: requested LoRA \(hash.prefix(12)) not found locally")
            connection.cancel()
            return
        }
        
        print("p2p: serving LoRA \(hash.prefix(12)) (\(data.count / 1024)KB) to peer")
        
        // Send as raw binary (QUIC/UDP handles chunking at transport layer)
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("p2p: send failed: \(error)")
            }
            connection.cancel()
        })
    }
    
    // MARK: - Receive LoRA from peer
    
    private func receiveLoRA(connection: NWConnection, hash: String) {
        var received = Data()
        
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1_000_000) { [weak self] data, _, isComplete, error in
                if let data {
                    received.append(data)
                }
                if isComplete || error != nil {
                    if received.count > 0 {
                        print("p2p: ✅ received LoRA \(hash.prefix(12)) (\(received.count / 1024)KB) from peer")
                        DispatchQueue.main.async {
                            self?.onLoRAReceived?(hash, received)
                        }
                    }
                    connection.cancel()
                } else {
                    readMore()
                }
            }
        }
        readMore()
    }
    
    func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        isAdvertising = false
        discoveredPeers = []
    }
}
