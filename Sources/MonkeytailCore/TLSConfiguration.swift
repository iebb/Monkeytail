import Foundation
import Security
import CryptoKit

public struct TLSConfiguration: @unchecked Sendable {
    public let identity: SecIdentity
    public let certificates: [SecCertificate]
    public let host: String
    public let port: Int
    public init(identity: SecIdentity, certificates: [SecCertificate], host: String, port: Int = 443) {
        self.identity = identity; self.certificates = certificates; self.host = host.lowercased(); self.port = port
    }
    public static func importPKCS12(_ data: Data, password: String, host: String, port: Int = 443) throws -> TLSConfiguration {
        guard data.count <= 5 * 1024 * 1024, !host.isEmpty else { throw ClientError("Choose a client identity up to 5 MB and enter its host.") }
        var imported: CFArray?
        var options: [String: Any] = [kSecImportExportPassphrase as String: password]
        #if os(macOS)
        guard #available(macOS 15, *) else { throw ClientError("Client identities require macOS 15 or later.") }
        options[kSecImportToMemoryOnly as String] = true
        #endif
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &imported)
        guard status == errSecSuccess, let values = imported as? [[String: Any]], let item = values.first, let raw = item[kSecImportItemIdentity as String] else { throw ClientError("Could not import PKCS#12 identity. Check its password (\(status)).") }
        return TLSConfiguration(identity: raw as! SecIdentity, certificates: item[kSecImportItemCertChain as String] as? [SecCertificate] ?? [], host: host, port: port)
    }
}
/// A server certificate trusted for one exact host and port: the per-host alternative to turning verification off.
public struct TrustedCertificate: Codable, Equatable, Identifiable, Sendable {
    public var host: String, port: Int, sha256: String, subject: String
    public var id: String { host + ":" + String(port) }
    public init(host: String, port: Int, sha256: String, subject: String) { self.host = host.lowercased(); self.port = port; self.sha256 = sha256; self.subject = subject }
    /// A credential when the system rejects the server but its leaf certificate matches a trusted fingerprint; otherwise the rejected leaf.
    public static func evaluate(_ space: URLProtectionSpace, trusted: [TrustedCertificate]) -> (credential: URLCredential?, rejected: TrustedCertificate?) {
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust, !SecTrustEvaluateWithError(trust, nil),
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return (nil, nil) }
        let details = CertificateDetails(leaf), candidate = TrustedCertificate(host: space.host, port: space.port, sha256: details.sha256, subject: details.subject)
        return trusted.contains { $0.id == candidate.id && $0.sha256 == candidate.sha256 } ? (URLCredential(trust: trust), nil) : (nil, candidate)
    }
}
public struct UntrustedCertificateError: LocalizedError, Sendable {
    public var certificate: TrustedCertificate
    public init(certificate: TrustedCertificate) { self.certificate = certificate }
    public var errorDescription: String? { String(localized: "The certificate for \(certificate.host):\(certificate.port) (\(certificate.subject)) is not trusted by this device.", bundle: .module) }
}
public struct CertificateDetails: Codable, Equatable, Identifiable, Sendable {
    public var id: String { sha256 }
    public var subject: String, sha256: String
    public var notBefore: Date?, notAfter: Date?
    public init(_ certificate: SecCertificate) {
        subject = SecCertificateCopySubjectSummary(certificate) as String? ?? "Certificate"
        let data = SecCertificateCopyData(certificate) as Data
        sha256 = SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined(separator: ":")
        // X.509 TBSCertificate validity is the fifth field after an optional version.
        struct DER {
            var tag: UInt8, data: Data
            var children: [DER] {
                var children: [DER] = [], index = 0, bytes = [UInt8](data)
                while index + 2 <= bytes.count {
                    let tag = bytes[index]; index += 1; let first = Int(bytes[index]); index += 1
                    var length = first
                    if first & 128 != 0 {
                        let count = first & 127; guard count > 0, count <= 4, index + count <= bytes.count else { break }; length = 0
                        for _ in 0..<count { length = length * 256 + Int(bytes[index]); index += 1 }
                    }
                    guard length >= 0, index + length <= bytes.count else { break }
                    children.append(DER(tag: tag, data: Data(bytes[index..<index + length]))); index += length
                }
                return children
            }
        }
        let tbs = DER(tag: 0, data: data).children.first?.children.first?.children ?? []
        let offset = tbs.first?.tag == 0xA0 ? 1 : 0
        if tbs.count > offset + 3 {
            let times = tbs[offset + 3].children
            func date(_ element: DER?) -> Date? {
                guard let element else { return nil }
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = element.tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
                formatter.twoDigitStartDate = Date(timeIntervalSince1970: -631152000)
                return formatter.date(from: String(decoding: element.data, as: UTF8.self))
            }
            notBefore = date(times.first); notAfter = date(times.dropFirst().first)
        }
    }
}
public struct TLSDetails: Codable, Equatable, Sendable {
    public var certificates: [CertificateDetails]
    public var version: String?, cipher: String?, alpn: String?
    public init(certificates: [CertificateDetails] = [], version: String? = nil, cipher: String? = nil, alpn: String? = nil) { self.certificates = certificates; self.version = version; self.cipher = cipher; self.alpn = alpn }
}
