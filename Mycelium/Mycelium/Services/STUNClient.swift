import Foundation
import Network

/// STUN client for discovering our public IP:port for NAT traversal.
/// Ported from spore-ios — same RFC 5389 binding request/response parsing.
class STUNClient {
    static let servers = [
        NWEndpoint.hostPort(host: "stun.l.google.com", port: 19302),
        NWEndpoint.hostPort(host: "stun.cloudflare.com", port: 3478)
    ]

    struct NATInfo {
        let publicAddress: String
        let publicPort: UInt16
    }

    static func discover(completion: @escaping (NATInfo?) -> Void) {
        let server = servers[0]
        let params = NWParameters.udp
        // Bypass Apple's "Limit IP Address Tracking" relay to get our real public IP
        params.prohibitConstrainedPaths = true
        let connection = NWConnection(to: server, using: params)

        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }

            let request = Self.buildBindingRequest()
            connection.send(content: request, completion: .contentProcessed { error in
                guard error == nil else {
                    completion(nil)
                    connection.cancel()
                    return
                }
            })

            connection.receiveMessage { data, _, _, error in
                defer { connection.cancel() }
                guard let data, error == nil else {
                    completion(nil)
                    return
                }
                let info = Self.parseBindingResponse(data)
                completion(info)
            }
        }

        connection.start(queue: .global())
    }

    // MARK: - STUN Protocol

    static func buildBindingRequest() -> Data {
        var data = Data()
        // Type: Binding Request (0x0001)
        data.append(contentsOf: [0x00, 0x01])
        // Length: 0
        data.append(contentsOf: [0x00, 0x00])
        // Magic Cookie
        data.append(contentsOf: [0x21, 0x12, 0xA4, 0x42])
        // Transaction ID (12 random bytes)
        var txID = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, 12, &txID)
        data.append(contentsOf: txID)
        return data
    }

    static func parseBindingResponse(_ data: Data) -> NATInfo? {
        guard data.count >= 20 else { return nil }
        let bytes = [UInt8](data)

        var offset = 20
        while offset + 4 <= bytes.count {
            let attrType = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            let attrLen = Int(UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3]))
            offset += 4

            guard offset + attrLen <= bytes.count else { break }

            // XOR-MAPPED-ADDRESS (0x0020) or MAPPED-ADDRESS (0x0001)
            if attrType == 0x0020 && attrLen >= 8 {
                let xorPort = UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3])
                let port = xorPort ^ 0x2112

                let xorIP: [UInt8] = [
                    bytes[offset + 4] ^ 0x21,
                    bytes[offset + 5] ^ 0x12,
                    bytes[offset + 6] ^ 0xA4,
                    bytes[offset + 7] ^ 0x42
                ]
                let ip = "\(xorIP[0]).\(xorIP[1]).\(xorIP[2]).\(xorIP[3])"
                return NATInfo(publicAddress: ip, publicPort: port)
            } else if attrType == 0x0001 && attrLen >= 8 {
                let port = UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3])
                let ip = "\(bytes[offset + 4]).\(bytes[offset + 5]).\(bytes[offset + 6]).\(bytes[offset + 7])"
                return NATInfo(publicAddress: ip, publicPort: port)
            }

            offset += attrLen
            if attrLen % 4 != 0 { offset += 4 - (attrLen % 4) }
        }
        return nil
    }
}
