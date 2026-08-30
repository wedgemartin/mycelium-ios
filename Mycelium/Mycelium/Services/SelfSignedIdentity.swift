import Foundation
import Network
import Security

/// Provides a self-signed TLS identity for the QUIC listener, loaded from a bundled p12.
///
/// Mycelium has no persistent Ed25519 keypair (unlike Spore), and peer authentication
/// isn't the security goal — LoRA content is public and SHA256-verified after transfer.
/// A QUIC/TLS *listener* still requires a local identity to present a server certificate,
/// so we ship a self-signed p12 (`mycelium-quic.p12`, passphrase "mycelium") in the bundle.
///
/// The client side uses `sec_protocol_options_set_verify_block { accept }`, so the
/// self-signed cert is accepted without a CA — giving encrypted QUIC/TLS 1.3 transport
/// without a PKI. Same approach Spore uses with `spore-quic.p12`.
enum SelfSignedIdentity {
    static let shared: sec_identity_t? = loadIdentity()

    private static func loadIdentity() -> sec_identity_t? {
        guard let url = Bundle.main.url(forResource: "mycelium-quic", withExtension: "p12"),
              let p12Data = try? Data(contentsOf: url) else {
            print("identity: mycelium-quic.p12 not found in bundle — QUIC listener disabled")
            return nil
        }

        let options: [String: Any] = [kSecImportExportPassphrase as String: "mycelium"]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess,
              let itemArray = items as? [[String: Any]],
              let first = itemArray.first,
              let secIdentity = first[kSecImportItemIdentity as String] else {
            print("identity: failed to import p12: \(status)")
            return nil
        }

        return sec_identity_create(secIdentity as! SecIdentity)
    }
}
