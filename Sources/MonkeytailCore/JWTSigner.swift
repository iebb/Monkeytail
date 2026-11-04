import Foundation
import CryptoKit
import Security

/// RFC 7519 tokens signed with HMAC, RSA PKCS#1 v1.5, RSA-PSS, or ECDSA (RFC 7518 JWS algorithms), as Postman's JWT Bearer helper sends them.
public enum JWTSigner {
    public static func token(_ auth: JWTAuth) throws -> String {
        let custom = try object(auth.header, name: "header")
        let typ = custom["typ"].map(json) ?? #""JWT""#
        let extra = custom.keys.filter { $0 != "alg" && $0 != "typ" }.sorted().map { json($0) + ":" + json(custom[$0]!) }
        let header = "{" + ([#""alg":"\#(auth.algorithm.rawValue)""#, #""typ":"# + typ] + extra).joined(separator: ",") + "}"
        _ = try object(auth.payload, name: "payload")
        let payload = minified(auth.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : auth.payload)
        let input = base64URL(Data(header.utf8)) + "." + base64URL(Data(payload.utf8))
        return input + "." + base64URL(try signature(Data(input.utf8), auth: auth))
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Removes insignificant whitespace while preserving key order and number spelling.
    static func minified(_ text: String) -> String {
        var result = "", inString = false, escaped = false
        for character in text {
            if inString {
                result.append(character)
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" { inString = true; result.append(character) } else if !character.isWhitespace { result.append(character) }
        }
        return result
    }

    private static func object(_ text: String, name: String) throws -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard let value = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else { throw ClientError("The JWT \(name) must be a JSON object.") }
        return value
    }
    private static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    private static func signature(_ input: Data, auth: JWTAuth) throws -> Data {
        let name = auth.algorithm.rawValue, bits = Int(name.suffix(3)) ?? 256
        switch name.prefix(2) {
        case "HS":
            guard !auth.secret.isEmpty else { throw ClientError("JWT \(name) needs a secret.") }
            var keyData = Data(auth.secret.utf8)
            if auth.secretIsBase64 {
                var text = auth.secret.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                while text.count % 4 != 0 { text += "=" }
                guard let decoded = Data(base64Encoded: text) else { throw ClientError("The JWT secret is not valid Base64.") }
                keyData = decoded
            }
            let key = SymmetricKey(data: keyData)
            switch bits {
            case 384: return Data(HMAC<SHA384>.authenticationCode(for: input, using: key))
            case 512: return Data(HMAC<SHA512>.authenticationCode(for: input, using: key))
            default: return Data(HMAC<SHA256>.authenticationCode(for: input, using: key))
            }
        case "ES":
            let pem = try pemText(auth.privateKey, name: name)
            do {
                switch bits {
                case 384: return try P384.Signing.PrivateKey(pemRepresentation: pem).signature(for: input).rawRepresentation
                case 512: return try P521.Signing.PrivateKey(pemRepresentation: pem).signature(for: input).rawRepresentation
                default: return try P256.Signing.PrivateKey(pemRepresentation: pem).signature(for: input).rawRepresentation
                }
            } catch { throw ClientError("JWT \(name) needs a PEM EC private key on curve P-\(bits == 512 ? 521 : bits).") }
        default:
            let key = try rsaKey(pemText(auth.privateKey, name: name))
            let pss = name.hasPrefix("PS")
            let algorithm: SecKeyAlgorithm = switch bits {
            case 384: pss ? .rsaSignatureMessagePSSSHA384 : .rsaSignatureMessagePKCS1v15SHA384
            case 512: pss ? .rsaSignatureMessagePSSSHA512 : .rsaSignatureMessagePKCS1v15SHA512
            default: pss ? .rsaSignatureMessagePSSSHA256 : .rsaSignatureMessagePKCS1v15SHA256
            }
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(key, algorithm, input as CFData, &error) as Data? else {
                throw ClientError("JWT \(name) signing failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown error").")
            }
            return signature
        }
    }

    private static func pemText(_ text: String, name: String) throws -> String {
        let pem = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pem.hasPrefix("-----BEGIN ") else { throw ClientError("JWT \(name) needs a PEM private key (-----BEGIN PRIVATE KEY-----).") }
        guard !pem.contains("ENCRYPTED") else { throw ClientError("Encrypted private keys are unsupported. Export the key without a passphrase.") }
        return pem
    }
    private static func rsaKey(_ pem: String) throws -> SecKey {
        let lines = pem.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let der = Data(base64Encoded: lines.filter { !$0.hasPrefix("-----") }.joined()), !der.isEmpty else { throw ClientError("The RSA private key is not valid PEM.") }
        let pkcs1 = lines.first?.contains("RSA PRIVATE KEY") == true ? der : try pkcs8RSAKey(der)
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary, &error) else {
            throw ClientError("The RSA private key could not be read.")
        }
        return key
    }
    /// Extracts the PKCS#1 key from a PKCS#8 PrivateKeyInfo, which Security does not import directly.
    private static func pkcs8RSAKey(_ der: Data) throws -> Data {
        let bytes = [UInt8](der), rsaEncryption: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]
        var index = 0
        func element() -> (tag: UInt8, start: Int, length: Int)? {
            guard index + 2 <= bytes.count else { return nil }
            let tag = bytes[index]; var length = Int(bytes[index + 1]); index += 2
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard (1...4).contains(count), index + count <= bytes.count else { return nil }
                length = bytes[index..<index + count].reduce(0) { $0 << 8 | Int($1) }; index += count
            }
            guard index + length <= bytes.count else { return nil }
            return (tag, index, length)
        }
        guard element()?.tag == 0x30, let version = element(), version.tag == 0x02 else { throw ClientError("The private key is not PKCS#8 or PKCS#1 PEM.") }
        index = version.start + version.length
        guard let algorithm = element(), algorithm.tag == 0x30, Array(bytes[algorithm.start..<algorithm.start + algorithm.length]).starts(with: rsaEncryption) else {
            throw ClientError("RS and PS algorithms need an RSA private key.")
        }
        index = algorithm.start + algorithm.length
        guard let key = element(), key.tag == 0x04 else { throw ClientError("The private key is not PKCS#8 or PKCS#1 PEM.") }
        return Data(bytes[key.start..<key.start + key.length])
    }
}
