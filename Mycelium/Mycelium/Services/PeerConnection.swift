import Foundation
import Network

/// Direct QUIC connection to a Mycelium peer with length-prefixed message framing.
/// Ported from spore-ios PeerConnection. Used for reliable transfer of LoRA adapters
/// (15MB+) peer-to-peer, replacing the fragile UDP single-send in the old PeerManager.
///
/// Framing: each message is [4-byte big-endian UInt32 length][payload].
/// Max message size raised to 32MB to accommodate large LoRA GGUF files.
class PeerConnection {
    let endpoint: NWEndpoint
    let connection: NWConnection
    var remoteAddr: String?
    var transport: String = "QUIC"
    var onReceiveMessage: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    private var keepaliveTimer: DispatchSourceTimer?
    static let pingData = "mycelium-ping".data(using: .utf8)!
    static let maxMessageSize = 32_000_000 // 32MB ceiling for LoRA transfers

    /// Create a QUIC outbound connection (port 9011 — Mycelium P2P).
    init(quicHost: String, port: UInt16 = 9011) {
        self.endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(quicHost),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let quicOptions = NWProtocolQUIC.Options(alpn: ["mycelium/1"])
        sec_protocol_options_set_peer_authentication_required(quicOptions.securityProtocolOptions, false)
        sec_protocol_options_set_verify_block(quicOptions.securityProtocolOptions, { _, _, completionHandler in
            completionHandler(true)
        }, DispatchQueue.global())
        let params = NWParameters(quic: quicOptions)
        // Prefer WiFi; avoid burning cellular data on 15MB transfers
        params.prohibitedInterfaceTypes = [.cellular]

        self.connection = NWConnection(to: endpoint, using: params)
    }

    /// Initialize with an already-established NWConnection (from hole-punch QUIC upgrade).
    init(existingConnection: NWConnection, remoteAddr: String) {
        self.connection = existingConnection
        self.endpoint = existingConnection.endpoint
        self.remoteAddr = remoteAddr
    }

    func connect(completion: @escaping (Bool) -> Void) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                completion(true)
                self.startReceiving()
            case .failed, .cancelled:
                completion(false)
            default:
                break
            }
        }
        connection.start(queue: .global())
    }

    /// Send a message with 4-byte big-endian length prefix.
    func send(message: Data) {
        var frame = Data()
        var length = UInt32(message.count).bigEndian
        frame.append(Data(bytes: &length, count: 4))
        frame.append(message)
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error {
                print("peer: send error: \(error)")
            }
        })
    }

    func disconnect() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        connection.cancel()
    }

    /// Start receiving messages and keepalive. Call after the connection is ready.
    func startReceiving() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                print("peer: connection to \(self?.remoteAddr?.prefix(16) ?? "?") dropped")
                self?.keepaliveTimer?.cancel()
                self?.onDisconnect?()
            default:
                break
            }
        }
        startKeepalive()
        receiveLoop()
    }

    private func startKeepalive() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self, self.connection.state == .ready else { return }
            var frame = Data()
            var length = UInt32(PeerConnection.pingData.count).bigEndian
            frame.append(Data(bytes: &length, count: 4))
            frame.append(PeerConnection.pingData)
            self.connection.send(content: frame, completion: .contentProcessed { _ in })
        }
        timer.resume()
        keepaliveTimer = timer
    }

    private var receiveBuffer = Data()

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_000_000) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processReceiveBuffer()
                self.receiveLoop()
            } else if isComplete || error != nil {
                print("peer: receive ended, disconnecting")
                self.keepaliveTimer?.cancel()
                self.onDisconnect?()
            }
        }
    }

    private func processReceiveBuffer() {
        while receiveBuffer.count >= 4 {
            let b0 = UInt32(receiveBuffer[receiveBuffer.startIndex])
            let b1 = UInt32(receiveBuffer[receiveBuffer.startIndex + 1])
            let b2 = UInt32(receiveBuffer[receiveBuffer.startIndex + 2])
            let b3 = UInt32(receiveBuffer[receiveBuffer.startIndex + 3])
            let msgLength = Int((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)

            guard msgLength > 0 && msgLength < PeerConnection.maxMessageSize else {
                receiveBuffer.removeAll()
                return
            }
            let totalNeeded = 4 + msgLength
            guard receiveBuffer.count >= totalNeeded else { return }

            let startIdx = receiveBuffer.startIndex
            let msgEnd = startIdx + 4 + msgLength
            let bufEnd = startIdx + totalNeeded

            guard msgEnd <= receiveBuffer.endIndex && bufEnd <= receiveBuffer.endIndex else {
                receiveBuffer.removeAll()
                return
            }

            let message = receiveBuffer.subdata(in: (startIdx + 4)..<msgEnd)
            receiveBuffer = Data(receiveBuffer[bufEnd...])

            if message == PeerConnection.pingData { continue }
            onReceiveMessage?(message)
        }
    }
}
