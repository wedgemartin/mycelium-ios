import Foundation
import Network

/// HolePunch coordinates NAT traversal between two Mycelium peers.
/// Flow: STUN → discover public endpoint → share via signaling → both peers punch → QUIC connects.
/// Ported from spore-ios. Mycelium has no persistent keypair, so QUIC uses a self-signed
/// identity (nil local identity + accept-all verify). Content is SHA256-verified after transfer.
class HolePunch {

    /// Our public endpoint as discovered by STUN
    private(set) var publicEndpoint: String?
    /// Local port used for all UDP operations (punch + QUIC listener share this)
    private(set) var localPort: UInt16 = 9011 // Mycelium uses 9011 (Spore uses 9001)

    struct PunchResult {
        let remoteHost: String
        let remotePort: UInt16
        let success: Bool
    }

    /// Discover our public endpoint via STUN.
    func start(completion: @escaping (String?) -> Void) {
        discoverViaSTUN(localPort: localPort, completion: completion)
    }

    private func discoverViaSTUN(localPort: UInt16, completion: @escaping (String?) -> Void) {
        let stunServer = NWEndpoint.hostPort(host: "stun.l.google.com", port: 19302)
        let params = NWParameters.udp
        params.prohibitConstrainedPaths = true

        let connection = NWConnection(to: stunServer, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }

            let request = STUNClient.buildBindingRequest()
            connection.send(content: request, completion: .contentProcessed { error in
                guard error == nil else {
                    connection.cancel()
                    completion(nil)
                    return
                }
            })

            connection.receiveMessage { [weak self] data, _, _, error in
                defer { connection.cancel() }
                guard let data, error == nil else {
                    completion(nil)
                    return
                }
                if let info = STUNClient.parseBindingResponse(data) {
                    let endpoint = "\(info.publicAddress):\(info.publicPort)"
                    self?.publicEndpoint = endpoint
                    print("holepunch: STUN → \(endpoint) (local port \(localPort))")
                    completion(endpoint)
                } else {
                    completion(nil)
                }
            }
        }
        connection.start(queue: .global())
    }

    /// Perform hole-punch to a remote peer endpoint. Both sides call this roughly simultaneously.
    func punch(remoteHost: String, remotePort: UInt16, completion: @escaping (PunchResult) -> Void) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(remoteHost),
            port: NWEndpoint.Port(rawValue: remotePort)!
        )

        let params = NWParameters.udp
        params.prohibitConstrainedPaths = true
        let connection = NWConnection(to: endpoint, using: params)

        var received = false
        var completed = false

        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }

            if let localEndpoint = connection.currentPath?.localEndpoint {
                print("holepunch: punching from local \(localEndpoint) → \(remoteHost):\(remotePort)")
            }

            // Send 10 punch packets over 5 seconds
            self.sendPunchPackets(connection: connection, count: 10, interval: 0.5) {
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    if !received && !completed {
                        completed = true
                        connection.cancel()
                        completion(PunchResult(remoteHost: remoteHost, remotePort: remotePort, success: false))
                    }
                }
            }

            self.receiveLoop(connection: connection) { _ in
                guard !completed else { return }
                received = true
                completed = true
                print("holepunch: ✅ received response from \(remoteHost):\(remotePort)")
                connection.cancel()
                completion(PunchResult(remoteHost: remoteHost, remotePort: remotePort, success: true))
            }
        }

        connection.start(queue: .global())
    }

    /// After successful punch, connect via QUIC to the remote peer on the punched path.
    func upgradeToQUIC(host: String, port: UInt16, completion: @escaping (NWConnection?) -> Void) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let options = NWProtocolQUIC.Options(alpn: ["mycelium/1"])
        sec_protocol_options_set_peer_authentication_required(options.securityProtocolOptions, false)
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, completionHandler in
            completionHandler(true)
        }, DispatchQueue.global())
        let params = NWParameters(quic: options)

        let connection = NWConnection(to: endpoint, using: params)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("holepunch: ✅ QUIC connection established to \(host):\(port)")
                completion(connection)
            case .failed(let error):
                print("holepunch: QUIC upgrade failed: \(error)")
                completion(nil)
            case .cancelled:
                completion(nil)
            default:
                break
            }
        }

        connection.start(queue: .global())

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if connection.state != .ready {
                connection.cancel()
            }
        }
    }

    // MARK: - Private

    private func sendPunchPackets(connection: NWConnection, count: Int, interval: TimeInterval, completion: @escaping () -> Void) {
        let punchData = "mycelium-punch".data(using: .utf8)!
        var sent = 0

        func sendNext() {
            guard sent < count else {
                completion()
                return
            }
            sent += 1
            connection.send(content: punchData, completion: .contentProcessed { _ in
                DispatchQueue.global().asyncAfter(deadline: .now() + interval) {
                    sendNext()
                }
            })
        }
        sendNext()
    }

    private func receiveLoop(connection: NWConnection, handler: @escaping (Data) -> Void) {
        connection.receiveMessage { data, _, _, error in
            if let data, error == nil {
                handler(data)
            } else {
                if connection.state == .ready {
                    self.receiveLoop(connection: connection, handler: handler)
                }
            }
        }
    }
}
