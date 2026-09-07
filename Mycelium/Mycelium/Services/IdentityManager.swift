import Foundation
import Observation
import CryptoKit
import Security

/// Persistent Ed25519 identity for Mycelium, shared with Spore where possible.
///
/// This replaces the old random `spore1mycelium####` throwaway address. The identity
/// is a Curve25519 signing keypair whose public key becomes the `spore1…` bech32 address
/// — the same identity model Spore uses, on the same network.
///
/// FEDERATION (Level 2): the key is stored in a **shared Keychain Access Group**
/// (`\(sharedAccessGroup)`). Both Mycelium and Spore (same Apple team) can read it, so a
/// user has ONE identity that posts spores AND publishes LoRAs. On first launch Mycelium:
///   1. reads the shared group (adopt an existing Spore identity if present),
///   2. else reads its own keychain (migration path),
///   3. else generates a new keypair and writes it to the shared group.
///
/// Anonymous by default — an identity is created automatically; a handle is optional.
@Observable
class IdentityManager {
    static let shared = IdentityManager()

    var address: String?
    var handle: String? {
        didSet { UserDefaults.standard.set(handle, forKey: "mycelium_handle") }
    }

    private var privateKey: Curve25519.Signing.PrivateKey?

    private let keychainService = "xyz.getspore.identity"   // shared service name across apps
    private let keychainAccount = "privateKey"
    // Shared access group — must match the entitlement (team-prefixed). Spore must add the
    // same group in a coordinated release for full cross-app sharing.
    private let sharedAccessGroup = "J5VW83FVVT.xyz.getspore.shared"

    init() {
        loadOrCreate()
        handle = UserDefaults.standard.string(forKey: "mycelium_handle")
    }

    var publicKey: Data? { privateKey?.publicKey.rawRepresentation }
    var isSetUp: Bool { privateKey != nil }

    /// Ensures an identity exists — anonymous by default. Idempotent.
    private func loadOrCreate() {
        // 1. Shared group (adopt Spore/other-app identity if present)
        if let data = loadKey(useSharedGroup: true) {
            adopt(data)
            return
        }
        // 2. This app's own (non-shared) keychain — migration / no-entitlement fallback
        if let data = loadKey(useSharedGroup: false) {
            adopt(data)
            // Promote into the shared group so Spore can adopt it too (best-effort).
            saveKey(data, useSharedGroup: true)
            return
        }
        // 3. Nothing exists — generate a fresh anonymous identity.
        _ = generate()
    }

    private func adopt(_ data: Data) {
        privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
        if let key = privateKey {
            address = bech32Encode(hrp: "spore", data: Data(key.publicKey.rawRepresentation))
        }
    }

    // MARK: - Key generation / restore

    @discardableResult
    func generate() -> String {
        let key = Curve25519.Signing.PrivateKey()
        privateKey = key
        // Write to shared group first (so Spore can share it); falls back to own keychain.
        if !saveKey(key.rawRepresentation, useSharedGroup: true) {
            saveKey(key.rawRepresentation, useSharedGroup: false)
        }
        address = bech32Encode(hrp: "spore", data: Data(key.publicKey.rawRepresentation))
        return BIP39.toMnemonic(entropy: [UInt8](key.rawRepresentation)).joined(separator: " ")
    }

    func restore(mnemonic: String) -> Bool {
        let words = mnemonic.split(separator: " ").map(String.init)
        guard let entropy = BIP39.toEntropy(words: words),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: Data(entropy).prefix(32)) else {
            return false
        }
        privateKey = key
        if !saveKey(key.rawRepresentation, useSharedGroup: true) {
            saveKey(key.rawRepresentation, useSharedGroup: false)
        }
        address = bech32Encode(hrp: "spore", data: Data(key.publicKey.rawRepresentation))
        return true
    }

    // MARK: - Signing (available now; adapter-signing wiring is a later pass)

    func sign(_ data: Data) -> Data? {
        try? privateKey?.signature(for: data)
    }

    /// The BIP39 recovery phrase for the current identity, so the user can back it up.
    /// Returns nil if no identity exists yet.
    func currentMnemonic() -> String? {
        guard let privateKey else { return nil }
        return BIP39.toMnemonic(entropy: [UInt8](privateKey.rawRepresentation)).joined(separator: " ")
    }

    // MARK: - Keychain

    func reset() {
        for shared in [true, false] {
            var query = baseQuery(useSharedGroup: shared)
            SecItemDelete(query as CFDictionary)
            _ = query // silence unused in release
        }
        privateKey = nil
        address = nil
        handle = nil
    }

    private func baseQuery(useSharedGroup: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        #if !targetEnvironment(simulator)
        if useSharedGroup {
            q[kSecAttrAccessGroup as String] = sharedAccessGroup
        }
        #endif
        return q
    }

    @discardableResult
    private func saveKey(_ data: Data, useSharedGroup: Bool) -> Bool {
        var query = baseQuery(useSharedGroup: useSharedGroup)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrIsInvisible as String] = true
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadKey(useSharedGroup: Bool) -> Data? {
        var query = baseQuery(useSharedGroup: useSharedGroup)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    // MARK: - Bech32

    func bech32Encode(hrp: String, data: Data) -> String {
        let converted = convertBits(data: [UInt8](data), fromBits: 8, toBits: 5, pad: true)
        return Bech32.encode(hrp: hrp, values: converted)
    }

    private func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8] {
        var acc = 0, bits = 0
        var result = [UInt8]()
        let maxv = (1 << toBits) - 1
        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad && bits > 0 {
            result.append(UInt8((acc << (toBits - bits)) & maxv))
        }
        return result
    }
}
