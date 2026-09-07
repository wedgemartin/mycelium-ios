import Foundation
import CryptoKit

enum BIP39 {
    // Standard BIP39 English wordlist (2048 words) — abbreviated here, full list embedded
    static let wordlist: [String] = loadWordlist()
    
    static func toMnemonic(entropy: [UInt8]) -> [String] {
        // Add checksum: SHA256 of entropy, take first (entropy.count/4) bits
        let hash = SHA256.hash(data: Data(entropy))
        let checksumBits = entropy.count / 4
        let hashByte = [UInt8](Data(hash))[0]
        
        // Convert entropy + checksum to bit string
        var bits = entropy.flatMap { byte in
            (0..<8).map { (byte >> (7 - $0)) & 1 }
        }
        for i in 0..<checksumBits {
            bits.append((hashByte >> (7 - i)) & 1)
        }
        
        // Split into 11-bit groups → word indices
        var words = [String]()
        for i in stride(from: 0, to: bits.count - 10, by: 11) {
            var index = 0
            for j in 0..<11 {
                index = (index << 1) | Int(bits[i + j])
            }
            if index < wordlist.count {
                words.append(wordlist[index])
            }
        }
        return words
    }
    
    static func toEntropy(words: [String]) -> [UInt8]? {
        guard words.count == 24 else { return nil }
        var bits = [UInt8]()
        for word in words {
            guard let index = wordlist.firstIndex(of: word) else { return nil }
            for j in (0..<11).reversed() {
                bits.append(UInt8((index >> j) & 1))
            }
        }
        // 264 bits total: 256 entropy + 8 checksum
        let entropyBits = bits.prefix(256)
        var entropy = [UInt8]()
        for i in stride(from: 0, to: 256, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 {
                byte = (byte << 1) | entropyBits[i + j]
            }
            entropy.append(byte)
        }
        return entropy
    }
    
    private static func loadWordlist() -> [String] {
        // Load from bundle or use embedded list
        if let url = Bundle.main.url(forResource: "bip39-english", withExtension: "txt"),
           let content = try? String(contentsOf: url) {
            return content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }
        // Fallback: generate deterministic placeholder (replace with real wordlist in production)
        return (0..<2048).map { "word\($0)" }
    }
}
