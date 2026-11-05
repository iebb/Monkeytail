import CryptoKit
import Foundation
import Security

/// The cryptography Insomnia's desktop client uses to sign in and read Cloud Sync: a libsodium sealed box for the login code,
/// AES-256-GCM and RSA-OAEP-256 for account and project keys, and gzip for stored documents.
enum SyncCrypto {
    /// Opens a libsodium `crypto_box_seal` box (X25519, XSalsa20-Poly1305, BLAKE2b nonce).
    static func openSealedBox(_ box: Data, publicKey: Data, secretKey: Data) throws -> Data {
        let box = [UInt8](box), invalid = ClientError("The sign-in code is invalid or expired. Sign in again to get a new one.")
        guard box.count >= 48, publicKey.count == 32, secretKey.count == 32 else { throw invalid }
        let ephemeral = Array(box[0..<32])
        let shared = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey)
            .sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(ephemeral)))
        let point = shared.withUnsafeBytes { [UInt8]($0) }
        let key = hsalsa20(key: point, input: [UInt8](repeating: 0, count: 16))
        let nonce = blake2b(ephemeral + [UInt8](publicKey), length: 24)
        let subkey = hsalsa20(key: key, input: Array(nonce[0..<16]))
        let mac = Array(box[32..<48]), ciphertext = Array(box[48...])
        var stream = salsa20Stream(key: subkey, nonce: Array(nonce[16..<24]), count: 32 + ciphertext.count)
        let expected = poly1305(ciphertext, key: Array(stream[0..<32]))
        guard zip(expected, mac).reduce(0, { $0 | ($1.0 ^ $1.1) }) == 0 else { throw invalid }
        stream.removeFirst(32)
        return Data(zip(ciphertext, stream).map { $0 ^ $1 })
    }

    /// Decrypts Insomnia's `{iv, t, ad, d}` AES-GCM message, all hex. `key` is a hex string or an `oct` JWK.
    static func decryptAES(_ message: Any?, key: Any?) throws -> Data {
        let failure = ClientError("Insomnia data could not be decrypted with this account's keys.")
        let message = (message as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? message
        guard let fields = message as? [String: Any], let iv = hex(fields["iv"]), let tag = hex(fields["t"]), let body = hex(fields["d"]),
              let raw = (key as? String).flatMap(hex) ?? ((key as? [String: Any])?["k"] as? String).flatMap(base64URL), [16, 24, 32].contains(raw.count),
              let box = try? AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: body, tag: tag),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: raw), authenticating: hex(fields["ad"]) ?? Data()) else { throw failure }
        return plain
    }

    /// Decrypts `encodeURIComponent`-wrapped JSON, as Insomnia stores account and project keys.
    static func decryptJSON(_ message: Any?, key: Any?) throws -> [String: Any] {
        try json(try decryptAES(message, key: key))
    }

    /// RSA-OAEP-SHA256 decryption of a hex ciphertext with a private JWK, returning the decoded JSON.
    static func decryptRSAJSON(_ hexText: String, privateKey jwk: [String: String]) throws -> [String: Any] {
        let failure = ClientError("Insomnia data could not be decrypted with this account's keys.")
        let names = ["n", "e", "d", "p", "q", "dp", "dq", "qi"]
        let parts = names.compactMap { jwk[$0].flatMap(base64URL) }
        guard parts.count == names.count, let cipher = hex(hexText) else { throw failure }
        let der = derSequence([derInteger(Data([0]))] + parts.map(derInteger))
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate, kSecAttrKeySizeInBits: parts[0].drop { $0 == 0 }.count * 8]
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil),
              let plain = SecKeyCreateDecryptedData(key, .rsaEncryptionOAEPSHA256, cipher as CFData, nil) as Data? else { throw failure }
        return try json(plain)
    }

    static func json(_ data: Data) throws -> [String: Any] {
        let text = String(decoding: data, as: UTF8.self)
        guard let object = try? JSONSerialization.jsonObject(with: Data((text.removingPercentEncoding ?? text).utf8)) as? [String: Any] else { throw ClientError("Insomnia sent a key in an unexpected format.") }
        return object
    }

    /// Inflates gzip data; anything without the gzip magic number is returned unchanged.
    static func gunzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data), failure = ClientError("Insomnia sent a document that could not be decompressed.")
        guard bytes.count >= 2, bytes[0] == 0x1f, bytes[1] == 0x8b else { return data }
        guard bytes.count >= 18, bytes[2] == 8 else { throw failure }
        let flags = bytes[3]; var index = 10
        if flags & 4 != 0 { guard index + 2 <= bytes.count else { throw failure }; index += 2 + Int(bytes[index]) | Int(bytes[index + 1]) << 8 }
        for flag in [UInt8(8), 16] where flags & flag != 0 { while index < bytes.count && bytes[index] != 0 { index += 1 }; index += 1 }
        if flags & 2 != 0 { index += 2 }
        guard index < bytes.count - 8, let inflated = try? (Data(bytes[index..<(bytes.count - 8)]) as NSData).decompressed(using: .zlib) as Data else { throw failure }
        return inflated
    }

    static func hex(_ value: Any?) -> Data? {
        guard let text = value as? String, text.count % 2 == 0 else { return nil }
        var data = Data(capacity: text.count / 2), index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            data.append(byte); index = next
        }
        return data
    }

    static func base64URL(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: value)
    }

    // MARK: DER

    private static func derLength(_ count: Int) -> [UInt8] {
        guard count >= 128 else { return [UInt8(count)] }
        var bytes: [UInt8] = [], value = count
        while value > 0 { bytes.insert(UInt8(value & 0xff), at: 0); value >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
    private static func derInteger(_ data: Data) -> Data {
        var bytes = Array(data.drop { $0 == 0 }); if bytes.isEmpty || bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return Data([0x02] + derLength(bytes.count) + bytes)
    }
    private static func derSequence(_ items: [Data]) -> Data {
        let body = items.reduce(Data(), +)
        return Data([0x30] + derLength(body.count)) + body
    }

    // MARK: Salsa20

    private static func load32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
    private static func store32(_ value: UInt32) -> [UInt8] { [UInt8(value & 0xff), UInt8(value >> 8 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 24)] }
    private static func rotl(_ value: UInt32, _ count: UInt32) -> UInt32 { value << count | value >> (32 - count) }

    private static func salsaState(key: [UInt8], input: [UInt8]) -> [UInt32] {
        [0x61707865, load32(key, 0), load32(key, 4), load32(key, 8), load32(key, 12), 0x3320646e, load32(input, 0), load32(input, 4),
         load32(input, 8), load32(input, 12), 0x79622d32, load32(key, 16), load32(key, 20), load32(key, 24), load32(key, 28), 0x6b206574]
    }
    private static func salsaRounds(_ state: [UInt32]) -> [UInt32] {
        var x = state
        func quarter(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            x[b] ^= rotl(x[a] &+ x[d], 7); x[c] ^= rotl(x[b] &+ x[a], 9); x[d] ^= rotl(x[c] &+ x[b], 13); x[a] ^= rotl(x[d] &+ x[c], 18)
        }
        for _ in 0..<10 {
            quarter(0, 4, 8, 12); quarter(5, 9, 13, 1); quarter(10, 14, 2, 6); quarter(15, 3, 7, 11)
            quarter(0, 1, 2, 3); quarter(5, 6, 7, 4); quarter(10, 11, 8, 9); quarter(15, 12, 13, 14)
        }
        return x
    }
    static func hsalsa20(key: [UInt8], input: [UInt8]) -> [UInt8] {
        let x = salsaRounds(salsaState(key: key, input: input))
        return [0, 5, 10, 15, 6, 7, 8, 9].flatMap { store32(x[$0]) }
    }
    static func salsa20Stream(key: [UInt8], nonce: [UInt8], count: Int) -> [UInt8] {
        var output: [UInt8] = [], counter: UInt64 = 0
        output.reserveCapacity(count + 64)
        while output.count < count {
            let state = salsaState(key: key, input: nonce + store32(UInt32(counter & 0xffffffff)) + store32(UInt32(counter >> 32)))
            output += zip(salsaRounds(state), state).flatMap { store32($0 &+ $1) }
            counter += 1
        }
        return Array(output.prefix(count))
    }

    // MARK: Poly1305

    static func poly1305(_ message: [UInt8], key: [UInt8]) -> [UInt8] {
        let mask: UInt32 = 0x3ffffff
        let r0 = load32(key, 0) & 0x3ffffff, r1 = load32(key, 3) >> 2 & 0x3ffff03, r2 = load32(key, 6) >> 4 & 0x3ffc0ff
        let r3 = load32(key, 9) >> 6 & 0x3f03fff, r4 = load32(key, 12) >> 8 & 0x00fffff
        let s1 = UInt64(r1 * 5), s2 = UInt64(r2 * 5), s3 = UInt64(r3 * 5), s4 = UInt64(r4 * 5)
        let (q0, q1, q2, q3, q4) = (UInt64(r0), UInt64(r1), UInt64(r2), UInt64(r3), UInt64(r4))
        var h0: UInt32 = 0, h1: UInt32 = 0, h2: UInt32 = 0, h3: UInt32 = 0, h4: UInt32 = 0, offset = 0
        while offset < message.count {
            var block = Array(message[offset..<min(offset + 16, message.count)]), high: UInt32 = 1 << 24
            if block.count < 16 { block.append(1); block += [UInt8](repeating: 0, count: 16 - block.count); high = 0 }
            h0 &+= load32(block, 0) & mask; h1 &+= load32(block, 3) >> 2 & mask; h2 &+= load32(block, 6) >> 4 & mask
            h3 &+= load32(block, 9) >> 6 & mask; h4 &+= load32(block, 12) >> 8 | high
            let (a0, a1, a2, a3, a4) = (UInt64(h0), UInt64(h1), UInt64(h2), UInt64(h3), UInt64(h4))
            let d0 = a0 * q0 + a1 * s4 + a2 * s3 + a3 * s2 + a4 * s1
            var d1 = a0 * q1 + a1 * q0 + a2 * s4 + a3 * s3 + a4 * s2
            var d2 = a0 * q2 + a1 * q1 + a2 * q0 + a3 * s4 + a4 * s3
            var d3 = a0 * q3 + a1 * q2 + a2 * q1 + a3 * q0 + a4 * s4
            var d4 = a0 * q4 + a1 * q3 + a2 * q2 + a3 * q1 + a4 * q0
            h0 = UInt32(d0 & 0x3ffffff); d1 += d0 >> 26
            h1 = UInt32(d1 & 0x3ffffff); d2 += d1 >> 26
            h2 = UInt32(d2 & 0x3ffffff); d3 += d2 >> 26
            h3 = UInt32(d3 & 0x3ffffff); d4 += d3 >> 26
            h4 = UInt32(d4 & 0x3ffffff)
            h0 &+= UInt32(d4 >> 26) &* 5; h1 &+= h0 >> 26; h0 &= mask
            offset += 16
        }
        var carry = h1 >> 26; h1 &= mask
        h2 &+= carry; carry = h2 >> 26; h2 &= mask
        h3 &+= carry; carry = h3 >> 26; h3 &= mask
        h4 &+= carry; carry = h4 >> 26; h4 &= mask
        h0 &+= carry &* 5; carry = h0 >> 26; h0 &= mask
        h1 &+= carry
        var g0 = h0 &+ 5; carry = g0 >> 26; g0 &= mask
        var g1 = h1 &+ carry; carry = g1 >> 26; g1 &= mask
        var g2 = h2 &+ carry; carry = g2 >> 26; g2 &= mask
        var g3 = h3 &+ carry; carry = g3 >> 26; g3 &= mask
        var g4 = h4 &+ carry &- (1 << 26)
        var select = (g4 >> 31) &- 1
        g0 &= select; g1 &= select; g2 &= select; g3 &= select; g4 &= select
        select = ~select
        h0 = h0 & select | g0; h1 = h1 & select | g1; h2 = h2 & select | g2; h3 = h3 & select | g3; h4 = h4 & select | g4
        let words = [h0 | h1 << 26, h1 >> 6 | h2 << 20, h2 >> 12 | h3 << 14, h3 >> 18 | h4 << 8]
        var tag: [UInt8] = [], sum: UInt64 = 0
        for index in 0..<4 {
            sum = UInt64(words[index]) + UInt64(load32(key, 16 + 4 * index)) + (sum >> 32)
            tag += store32(UInt32(sum & 0xffffffff))
        }
        return tag
    }

    // MARK: BLAKE2b

    private static let blakeIV: [UInt64] = [0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
                                            0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179]
    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4], [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13], [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11], [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5], [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
    ]

    static func blake2b(_ input: [UInt8], length: Int) -> [UInt8] {
        var h = blakeIV; h[0] ^= 0x01010000 ^ UInt64(length)
        var offset = 0
        repeat {
            let last = input.count - offset <= 128
            var block = Array(input[offset..<min(offset + 128, input.count)]); block += [UInt8](repeating: 0, count: 128 - block.count)
            let m = (0..<16).map { word in (0..<8).reduce(UInt64(0)) { $0 | UInt64(block[word * 8 + $1]) << (8 * UInt64($1)) } }
            offset = min(offset + 128, input.count)
            var v = h + blakeIV
            v[12] ^= UInt64(offset); if last { v[14] = ~v[14] }
            func mix(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
                v[a] = v[a] &+ v[b] &+ x; v[d] = (v[d] ^ v[a]).rotatedRight(32)
                v[c] = v[c] &+ v[d]; v[b] = (v[b] ^ v[c]).rotatedRight(24)
                v[a] = v[a] &+ v[b] &+ y; v[d] = (v[d] ^ v[a]).rotatedRight(16)
                v[c] = v[c] &+ v[d]; v[b] = (v[b] ^ v[c]).rotatedRight(63)
            }
            for round in 0..<12 {
                let s = sigma[round % 10]
                mix(0, 4, 8, 12, m[s[0]], m[s[1]]); mix(1, 5, 9, 13, m[s[2]], m[s[3]]); mix(2, 6, 10, 14, m[s[4]], m[s[5]]); mix(3, 7, 11, 15, m[s[6]], m[s[7]])
                mix(0, 5, 10, 15, m[s[8]], m[s[9]]); mix(1, 6, 11, 12, m[s[10]], m[s[11]]); mix(2, 7, 8, 13, m[s[12]], m[s[13]]); mix(3, 4, 9, 14, m[s[14]], m[s[15]])
            }
            for index in 0..<8 { h[index] ^= v[index] ^ v[index + 8] }
            if last { break }
        } while true
        return Array(h.flatMap { word in (0..<8).map { UInt8(word >> (8 * UInt64($0)) & 0xff) } }.prefix(length))
    }
}

private extension UInt64 {
    func rotatedRight(_ count: UInt64) -> UInt64 { self >> count | self << (64 - count) }
}
