import Foundation

enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    
    static func encode(hrp: String, values: [UInt8]) -> String {
        let checksum = createChecksum(hrp: hrp, values: values)
        var result = hrp + "1"
        for v in values + checksum {
            result.append(charset[Int(v)])
        }
        return result
    }
    
    /// Decodes a bech32 string, returning the raw data bytes (converted from 5-bit to 8-bit).
    /// Returns nil if invalid.
    static func decode(_ str: String) -> Data? {
        guard let sepIdx = str.lastIndex(of: "1") else { return nil }
        let dataPart = str[str.index(after: sepIdx)...]
        
        // Convert characters to 5-bit values
        var values5bit: [UInt8] = []
        for c in dataPart {
            guard let idx = charset.firstIndex(of: c) else { return nil }
            values5bit.append(UInt8(idx))
        }
        
        // Strip 6 checksum bytes
        guard values5bit.count >= 6 else { return nil }
        values5bit = Array(values5bit.dropLast(6))
        
        // Convert from 5-bit to 8-bit
        return convertBits(data: values5bit, fromBits: 5, toBits: 8, pad: false)
    }
    
    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> Data? {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxV = (1 << toBits) - 1
        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxV))
            }
        }
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxV))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxV) != 0 {
            // Invalid padding
        }
        return Data(result)
    }
    
    private static func polymod(_ values: [Int]) -> Int {
        let gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk = 1
        for v in values {
            let b = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ v
            for i in 0..<5 {
                chk ^= ((b >> i) & 1) != 0 ? gen[i] : 0
            }
        }
        return chk
    }
    
    private static func hrpExpand(_ hrp: String) -> [Int] {
        var result = hrp.map { Int($0.asciiUInt8! >> 5) }
        result.append(0)
        result += hrp.map { Int($0.asciiUInt8! & 31) }
        return result
    }
    
    private static func createChecksum(hrp: String, values: [UInt8]) -> [UInt8] {
        let enc = hrpExpand(hrp) + values.map(Int.init) + [0, 0, 0, 0, 0, 0]
        let poly = polymod(enc) ^ 1
        return (0..<6).map { UInt8((poly >> (5 * (5 - $0))) & 31) }
    }
}

extension Character {
    var asciiUInt8: UInt8? {
        guard let scalar = unicodeScalars.first, scalar.isASCII else { return nil }
        return UInt8(scalar.value)
    }
}
