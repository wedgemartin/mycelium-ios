import Foundation
import Network
import Observation
import CryptoKit

/// Handles peer discovery and direct P2P LoRA transfer between Mycelium devices.
///
/// Two discovery paths:
///  1. LAN — mDNS (`_mycelium._udp`) for same-WiFi peers (fast path).
///  2. Internet — substrate `/signal` WebSocket + STUN hole-punch + QUIC-direct
///     for peers across the internet (BitTorrent-like content distribution).
///
/// LoRA transfer runs over a reliable QUIC connection with length-prefixed framing
/// (`PeerConnection`), so 15MB adapters transfer without the packet loss the old
/// UDP single-send suffered. The bot remains the seeder-of-last-resort.
@Observable
class PeerManager {
    var discoveredPeers: [Peer] = []
    var isAdvertising = false

    struct Peer: Identifiable {
        let id: String       // peer address
        let host: String
        let port: UInt16
        var availableLoRAs: [String] = [] // hashes this peer has
        var transport: String = "LAN"     // "LAN" | "QUIC"
    }

    // MARK: - Config
    private let serviceType = "_mycelium._udp"
    private let quicPort: UInt16 = 9011
    private let substrateWSURL = "wss://substrate.getspore.xyz:30880/signal"

    // MARK: - State
    private var myAddress: String = ""
    private var myLoRAHashes: [String] = []
    private var listener: NWListener?          // mDNS UDP listener (LAN peer list exchange)
    private var quicListener: NWListener?       // QUIC listener for direct transfers (port 9011)
    private var browser: NWBrowser?
    private var signalSocket: URLSessionWebSocketTask?
    private let holePunch = HolePunch()
    private var publicEndpoint: String?
    private var directPeers: [String: PeerConnection] = [:]  // addr -> live QUIC connection
    private var punchFailed: Set<String> = []
    private var connectingPeers: Set<String> = []
    private let lock = NSLock()

    // In-flight LoRA receive buffers keyed by hash
    private var pendingReceives: [String: (expected: Int, data: Data)] = [:]
    private var activeReceiveHash: String?  // hash of the transfer currently streaming

    // Callback when a LoRA is fully received from a peer
    var onLoRAReceived: ((String, Data) -> Void)? // (hash, data)

    // MARK: - Lifecycle

    func start(address: String, installedHashes: [String]) {
        myAddress = address
        myLoRAHashes = installedHashes
        startAdvertising()   // LAN mDNS
        startBrowsing()      // LAN mDNS
        startQUICListener()  // internet direct transfers
        discoverPublicEndpoint() // STUN, then connect signaling
    }

    func updateHashes(_ hashes: [String]) {
        myLoRAHashes = hashes
    }

    func stop() {
        listener?.cancel()
        quicListener?.cancel()
        browser?.cancel()
        signalSocket?.cancel()
        lock.lock()
        directPeers.values.forEach { $0.disconnect() }
        directPeers.removeAll()
        lock.unlock()
        listener = nil; quicListener = nil; browser = nil; signalSocket = nil
        isAdvertising = false
        discoveredPeers = []
    }

    /// Check if any discovered peer has a given LoRA hash.
    func peerWith(loraHash: String) -> Peer? {
        discoveredPeers.first { $0.availableLoRAs.contains(loraHash) }
    }

    // MARK: - Request a LoRA from a peer

    /// Request a LoRA from a peer. Prefers a live QUIC connection; establishes one if needed.
    func requestLoRA(hash: String, from peer: Peer) {
        // If we already have a direct QUIC connection to this peer, use it.
        lock.lock()
        let existing = directPeers[peer.id]
        lock.unlock()
        if let existing {
            print("p2p: requesting \(hash.prefix(12)) over existing QUIC to \(peer.id.prefix(12))")
            sendLoRARequest(hash: hash, over: existing)
            return
        }

        // Otherwise open a fresh QUIC connection to the peer's host:port.
        print("p2p: opening QUIC to \(peer.host):\(peer.port) for \(hash.prefix(12))")
        let conn = PeerConnection(quicHost: peer.host, port: peer.port)
        conn.onReceiveMessage = { [weak self] data in
            self?.handlePeerMessage(data, from: peer.id)
        }
        conn.connect { [weak self] ok in
            guard let self else { return }
            if ok {
                self.lock.lock(); self.directPeers[peer.id] = conn; self.lock.unlock()
                self.sendLoRARequest(hash: hash, over: conn)
            } else {
                print("p2p: QUIC connect to \(peer.host) failed")
            }
        }
    }

    private func sendLoRARequest(hash: String, over conn: PeerConnection) {
        let req = "LORA_REQ:\(hash)".data(using: .utf8)!
        conn.send(message: req)
    }

    // MARK: - QUIC listener (serve LoRAs to peers)

    private func startQUICListener() {
        do {
            let quicOptions = NWProtocolQUIC.Options(alpn: ["mycelium/1"])
            sec_protocol_options_set_peer_authentication_required(quicOptions.securityProtocolOptions, false)
            sec_protocol_options_set_verify_block(quicOptions.securityProtocolOptions, { _, _, completionHandler in
                completionHandler(true)
            }, DispatchQueue.global())
            // A self-signed identity is required for a QUIC/TLS listener.
            if let identity = SelfSignedIdentity.shared {
                sec_protocol_options_set_local_identity(quicOptions.securityProtocolOptions, identity)
            }
            let params = NWParameters(quic: quicOptions)
            params.allowLocalEndpointReuse = true

            quicListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: quicPort)!)
            quicListener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingQUIC(connection)
            }
            quicListener?.stateUpdateHandler = { state in
                if case .ready = state {
                    print("p2p: QUIC listener ready on \(self.quicPort)")
                }
            }
            quicListener?.start(queue: .global())
        } catch {
            print("p2p: failed to start QUIC listener: \(error)")
        }
    }

    private func handleIncomingQUIC(_ connection: NWConnection) {
        let peerConn = PeerConnection(existingConnection: connection, remoteAddr: "inbound")
        peerConn.onReceiveMessage = { [weak self] data in
            self?.handlePeerMessage(data, from: "inbound", over: peerConn)
        }
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                peerConn.startReceiving()
            }
        }
        connection.start(queue: .global())
    }

    // MARK: - Peer message handling (both directions)

    private func handlePeerMessage(_ data: Data, from addr: String, over conn: PeerConnection? = nil) {
        // Control messages are short UTF-8 strings with known prefixes.
        // LoRA payload chunks are raw binary appended to the active transfer.
        if let str = controlString(data) {
            if str == "LORA_LIST?" {
                let response = "LORA_LIST:" + myLoRAHashes.joined(separator: ",")
                conn?.send(message: response.data(using: .utf8)!)
                return
            }
            if str.hasPrefix("LORA_LIST:") {
                let hashes = String(str.dropFirst("LORA_LIST:".count)).split(separator: ",").map(String.init)
                updatePeerHashes(addr: addr, hashes: hashes)
                return
            }
            if str.hasPrefix("LORA_REQ:") {
                let hash = String(str.dropFirst("LORA_REQ:".count))
                if let conn { serveLoRA(hash: hash, over: conn) }
                return
            }
            if str.hasPrefix("LORA_HDR:") {
                // "LORA_HDR:<hash>:<totalBytes>" — begins a transfer.
                let rest = str.dropFirst("LORA_HDR:".count)
                if let colon = rest.lastIndex(of: ":"),
                   let total = Int(rest[rest.index(after: colon)...]) {
                    let hash = String(rest[..<colon])
                    lock.lock()
                    activeReceiveHash = hash
                    pendingReceives[hash] = (expected: total, data: Data())
                    lock.unlock()
                    print("p2p: incoming LoRA \(hash.prefix(12)) — \(total / 1024)KB")
                }
                return
            }
            if str.hasPrefix("LORA_END:") {
                let hash = String(str.dropFirst("LORA_END:".count))
                finalizeReceive(hash: hash)
                return
            }
        }
        // Raw binary chunk → append to the active transfer.
        appendChunk(data)
    }

    /// Returns the message as a control string only if it is a short, valid-UTF8 command.
    /// Guards against a binary chunk coincidentally decoding as UTF-8.
    private func controlString(_ data: Data) -> String? {
        guard data.count < 256, let s = String(data: data, encoding: .utf8) else { return nil }
        let prefixes = ["LORA_LIST?", "LORA_LIST:", "LORA_REQ:", "LORA_HDR:", "LORA_END:"]
        return prefixes.contains(where: { s.hasPrefix($0) }) ? s : nil
    }

    // MARK: - Serving a LoRA (chunked over framed QUIC)

    private func serveLoRA(hash: String, over conn: PeerConnection) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let loraPath = docs.appendingPathComponent("loras/\(hash).gguf")
        guard let data = try? Data(contentsOf: loraPath) else {
            print("p2p: requested LoRA \(hash.prefix(12)) not found locally")
            return
        }
        print("p2p: serving LoRA \(hash.prefix(12)) (\(data.count / 1024)KB)")

        // Header announces the transfer + total size.
        conn.send(message: "LORA_HDR:\(hash):\(data.count)".data(using: .utf8)!)

        // Send 512KB raw chunks, each wrapped in PeerConnection's length-prefix framing.
        let chunkSize = 512 * 1024
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            conn.send(message: data.subdata(in: offset..<end))
            offset = end
        }

        // End marker triggers reassembly + SHA verification on the receiver.
        conn.send(message: "LORA_END:\(hash)".data(using: .utf8)!)
    }

    private func appendChunk(_ data: Data) {
        lock.lock()
        if let hash = activeReceiveHash, var entry = pendingReceives[hash] {
            entry.data.append(data)
            pendingReceives[hash] = entry
        }
        lock.unlock()
    }

    private func finalizeReceive(hash: String) {
        lock.lock()
        let entry = pendingReceives.removeValue(forKey: hash)
        if activeReceiveHash == hash { activeReceiveHash = nil }
        lock.unlock()
        guard let entry else { return }
        guard entry.data.count >= entry.expected else {
            print("p2p: ⚠️ incomplete LoRA \(hash.prefix(12)): \(entry.data.count)/\(entry.expected) bytes — discarding")
            return
        }
        // Verify content integrity: the LoRA is addressed by SHA256 of its bytes.
        let digest = SHA256.hash(data: entry.data).map { String(format: "%02x", $0) }.joined()
        guard digest == hash else {
            print("p2p: ⚠️ SHA256 mismatch for \(hash.prefix(12)) (got \(digest.prefix(12))) — discarding")
            return
        }
        print("p2p: ✅ received + verified LoRA \(hash.prefix(12)) (\(entry.data.count / 1024)KB)")
        DispatchQueue.main.async { [weak self] in
            self?.onLoRAReceived?(hash, entry.data)
        }
    }

    private func updatePeerHashes(addr: String, hashes: [String]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let idx = self.discoveredPeers.firstIndex(where: { $0.id == addr }) {
                self.discoveredPeers[idx].availableLoRAs = hashes
            } else {
                // A hole-punched internet peer reporting its LoRA list — add it so
                // peerWith(loraHash:) can find it. host is the peer address itself;
                // requestLoRA will route over the existing directPeers[addr] connection.
                let peer = Peer(id: addr, host: addr, port: self.quicPort,
                                availableLoRAs: hashes, transport: "QUIC")
                self.discoveredPeers.append(peer)
                print("p2p: internet peer \(addr.prefix(12)) has \(hashes.count) LoRAs")
            }
        }
    }

    // MARK: - STUN public endpoint + signaling

    private func discoverPublicEndpoint() {
        holePunch.start { [weak self] endpoint in
            guard let self, let endpoint else {
                print("p2p: STUN discovery failed")
                return
            }
            self.publicEndpoint = endpoint
            print("p2p: public endpoint \(endpoint)")
            self.connectSignaling()
            self.registerEndpoint()
        }
    }

    private func registerEndpoint() {
        // Advertise our public endpoint + IPv6 to the substrate so peers can find us.
        guard let endpoint = publicEndpoint, !myAddress.isEmpty else { return }
        var endpoints = [endpoint]
        if let ipv6 = getIPv6Address() {
            endpoints.append("[\(ipv6)]:\(quicPort)")
        }
        guard let url = URL(string: "https://substrate.getspore.xyz:30880/register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "pubkey": myAddress,
            "app": "mycelium",
            "endpoints": endpoints,
            "loras": myLoRAHashes
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - Signaling WebSocket

    struct SignalMessage: Codable {
        let type: String   // "offer" | "answer"
        let to: String
        let from: String
        let sdp: String?
    }

    private func connectSignaling() {
        guard let url = URL(string: substrateWSURL) else { return }
        let session = URLSession(configuration: .default)
        signalSocket = session.webSocketTask(with: url)
        signalSocket?.resume()
        receiveSignal()
        print("p2p: signaling connected")
    }

    private func receiveSignal() {
        signalSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                self.handleSignal(text)
            case .failure(let error):
                print("p2p: signal error: \(error)")
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { self.connectSignaling() }
                return
            default:
                break
            }
            self.receiveSignal()
        }
    }

    private func handleSignal(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(SignalMessage.self, from: data) else { return }
        // Already connected directly? skip.
        lock.lock(); let have = directPeers[msg.from] != nil; lock.unlock()
        if have { return }

        switch msg.type {
        case "offer":
            // Peer wants to connect. Reply with our endpoint, then punch toward theirs.
            if let endpoint = publicEndpoint {
                sendSignal(type: "answer", to: msg.from, sdp: endpoint)
            }
            if let sdp = msg.sdp { startHolePunch(to: sdp, addr: msg.from) }
        case "answer":
            if let sdp = msg.sdp { startHolePunch(to: sdp, addr: msg.from) }
        default:
            break
        }
    }

    private func sendSignal(type: String, to: String, sdp: String) {
        let msg = SignalMessage(type: type, to: to, from: myAddress, sdp: sdp)
        guard let data = try? JSONEncoder().encode(msg),
              let text = String(data: data, encoding: .utf8) else { return }
        signalSocket?.send(.string(text)) { error in
            if let error { print("p2p: signal send error: \(error)") }
        }
    }

    /// Initiate a connection to a peer by address (called when we want their LoRA).
    func connectToInternetPeer(addr: String) {
        guard let endpoint = publicEndpoint else { return }
        lock.lock()
        let alreadyHave = directPeers[addr] != nil || connectingPeers.contains(addr)
        if !alreadyHave { connectingPeers.insert(addr) }
        lock.unlock()
        guard !alreadyHave else { return }
        sendSignal(type: "offer", to: addr, sdp: endpoint)
    }

    // MARK: - Hole punch → QUIC upgrade

    private func startHolePunch(to endpoint: String, addr: String) {
        lock.lock()
        if directPeers[addr] != nil || punchFailed.contains(addr) { lock.unlock(); return }
        connectingPeers.insert(addr)
        lock.unlock()

        let parts = endpoint.components(separatedBy: ":")
        guard parts.count == 2, let port = UInt16(parts[1]) else { return }
        let host = parts[0]
        print("p2p: hole-punching to \(endpoint)")

        holePunch.punch(remoteHost: host, remotePort: port) { [weak self] result in
            guard let self else { return }
            if result.success {
                self.holePunch.upgradeToQUIC(host: host, port: port) { connection in
                    self.lock.lock(); self.connectingPeers.remove(addr); self.lock.unlock()
                    if let connection {
                        print("p2p: ✅ direct QUIC via hole-punch to \(endpoint)")
                        self.addDirectPeer(connection: connection, addr: addr)
                    } else {
                        self.lock.lock(); self.punchFailed.insert(addr); self.lock.unlock()
                    }
                }
            } else {
                self.lock.lock(); self.connectingPeers.remove(addr); self.punchFailed.insert(addr); self.lock.unlock()
                print("p2p: punch failed to \(endpoint), will use bot")
            }
        }
    }

    private func addDirectPeer(connection: NWConnection, addr: String) {
        let peer = PeerConnection(existingConnection: connection, remoteAddr: addr)
        peer.onReceiveMessage = { [weak self] data in
            self?.handlePeerMessage(data, from: addr, over: peer)
        }
        peer.onDisconnect = { [weak self] in
            self?.lock.lock(); self?.directPeers.removeValue(forKey: addr); self?.lock.unlock()
        }
        lock.lock(); directPeers[addr] = peer; lock.unlock()
        peer.startReceiving()
        // Ask what LoRAs they have
        peer.send(message: "LORA_LIST?".data(using: .utf8)!)
    }

    // MARK: - IPv6 discovery (global only — site-local filter baked in)

    private func getIPv6Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee.ifa_addr.pointee
            guard addr.sa_family == UInt8(AF_INET6) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name == "pdp_ip0" || name == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getnameinfo(sa, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            }
            guard result == 0 else { continue }

            let ip = String(cString: hostname)
            let cleanIP = (ip.components(separatedBy: "%").first ?? ip).lowercased()
            // Only advertise genuinely global IPv6 addresses.
            if cleanIP == "::1" || cleanIP == "::" { continue }
            if cleanIP.hasPrefix("fe80") || cleanIP.hasPrefix("fe9") || cleanIP.hasPrefix("fea") || cleanIP.hasPrefix("feb") { continue } // link-local
            if cleanIP.hasPrefix("fec") || cleanIP.hasPrefix("fed") || cleanIP.hasPrefix("fee") || cleanIP.hasPrefix("fef") { continue } // site-local (deprecated)
            if cleanIP.hasPrefix("fc") || cleanIP.hasPrefix("fd") { continue } // unique-local
            print("p2p: found global IPv6: \(cleanIP) on \(name)")
            return cleanIP
        }
        return nil
    }

    // MARK: - LAN mDNS advertising/browsing (fast path for same-WiFi)

    private func startAdvertising() {
        do {
            let params = NWParameters.udp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: 9010)!)
            listener?.service = NWListener.Service(name: myAddress.prefix(20).description, type: serviceType)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleLANConnection(connection)
            }
            listener?.stateUpdateHandler = { state in
                if case .ready = state { print("p2p: LAN advertising on 9010") }
            }
            listener?.start(queue: .global())
            isAdvertising = true
        } catch {
            print("p2p: failed to start LAN listener: \(error)")
        }
    }

    private func startBrowsing() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: descriptor, using: params)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results { self?.handleLANDiscovery(result) }
        }
        browser?.start(queue: .global())
        print("p2p: browsing LAN for peers...")
    }

    private func handleLANDiscovery(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }
        if name == myAddress.prefix(20).description { return }

        let connection = NWConnection(to: result.endpoint, using: .udp)
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                let request = "LORA_LIST?".data(using: .utf8)!
                connection.send(content: request, completion: .contentProcessed { _ in })
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                    guard let data, let response = String(data: data, encoding: .utf8),
                          response.hasPrefix("LORA_LIST:") else { connection.cancel(); return }
                    let hashes = String(response.dropFirst("LORA_LIST:".count)).split(separator: ",").map(String.init)
                    if let path = connection.currentPath, let endpoint = path.remoteEndpoint,
                       case .hostPort(let host, _) = endpoint {
                        // LAN peers serve over QUIC on 9011 too.
                        let peer = Peer(id: name, host: "\(host)", port: self?.quicPort ?? 9011,
                                        availableLoRAs: hashes, transport: "LAN")
                        DispatchQueue.main.async {
                            if !(self?.discoveredPeers.contains(where: { $0.id == name }) ?? false) {
                                self?.discoveredPeers.append(peer)
                                print("p2p: discovered LAN peer \(name) with \(hashes.count) LoRAs")
                            }
                        }
                    }
                    connection.cancel()
                }
            }
        }
        connection.start(queue: .global())
    }

    private func handleLANConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
                    guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
                    if request == "LORA_LIST?" {
                        let response = "LORA_LIST:" + self.myLoRAHashes.joined(separator: ",")
                        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    }
                }
            }
        }
        connection.start(queue: .global())
    }
}
