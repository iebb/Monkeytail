import XCTest
import CryptoKit
import Security
@testable import MonkeytailCore

final class JWTTests: XCTestCase {
    private func jwt(_ algorithm: JWTAlgorithm, secret: String = "", key: String = "", payload: String = #"{"sub":"42"}"#, header: String = "{}") -> JWTAuth {
        var auth = JWTAuth(); auth.algorithm = algorithm; auth.secret = secret; auth.privateKey = key; auth.payload = payload; auth.header = header; return auth
    }
    private func parts(_ token: String) throws -> (input: Data, signature: Data, header: [String: Any]) {
        let pieces = token.split(separator: ".").map(String.init); XCTAssertEqual(pieces.count, 3)
        func decode(_ text: String) -> Data { var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); while value.count % 4 != 0 { value += "=" }; return Data(base64Encoded: value)! }
        return (Data((pieces[0] + "." + pieces[1]).utf8), decode(pieces[2]), try XCTUnwrap(JSONSerialization.jsonObject(with: decode(pieces[0])) as? [String: Any]))
    }
    private func pem(_ der: [UInt8], label: String) -> String {
        "-----BEGIN \(label)-----\n" + Data(der).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed]) + "\n-----END \(label)-----"
    }
    private func der(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        var length: [UInt8] = []; var count = content.count
        if count < 128 { length = [UInt8(count)] } else { while count > 0 { length.insert(UInt8(count & 0xff), at: 0); count >>= 8 }; length.insert(0x80 | UInt8(length.count), at: 0) }
        return [tag] + length + content
    }

    func testHMACTokensMatchReferenceVectors() throws {
        XCTAssertEqual(try JWTSigner.token(jwt(.hs256, secret: "your-256-bit-secret", payload: "{\n  \"sub\": \"1234567890\",\n  \"name\": \"John Doe\",\n  \"iat\": 1516239022\n}")),
                       "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c")
        var base64 = jwt(.hs384, secret: "c2VjcmV0LWtleQ==", payload: #"{"sub": "42", "scope": ["a", "b"], "n": 1.50}"#, header: #"{"kid": "k1", "alg": "none"}"#); base64.secretIsBase64 = true
        XCTAssertEqual(try JWTSigner.token(base64), "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCIsImtpZCI6ImsxIn0.eyJzdWIiOiI0MiIsInNjb3BlIjpbImEiLCJiIl0sIm4iOjEuNTB9.lDoiAVtFUlkQFZW006iVxOHvWEvFqDC2sNHNSzd1tc3al-FHIA8cko-OnJujUVOq")
        XCTAssertThrowsError(try JWTSigner.token(jwt(.hs512)))
        XCTAssertThrowsError(try JWTSigner.token(jwt(.hs256, secret: "s", payload: "[1]")))
        XCTAssertThrowsError(try JWTSigner.token(jwt(.hs256, secret: "s", header: "nope")))
    }

    func testRSAAndPSSTokensVerifyForPKCS1AndPKCS8Keys() throws {
        var error: Unmanaged<CFError>?
        let key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, &error)), publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let pkcs1 = [UInt8](try XCTUnwrap(SecKeyCopyExternalRepresentation(key, &error) as Data?))
        let pkcs8 = der(0x30, der(0x02, [0]) + der(0x30, [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]) + der(0x04, pkcs1))
        let cases: [(JWTAlgorithm, SecKeyAlgorithm)] = [(.rs256, .rsaSignatureMessagePKCS1v15SHA256), (.rs384, .rsaSignatureMessagePKCS1v15SHA384), (.rs512, .rsaSignatureMessagePKCS1v15SHA512),
                                                        (.ps256, .rsaSignatureMessagePSSSHA256), (.ps384, .rsaSignatureMessagePSSSHA384), (.ps512, .rsaSignatureMessagePSSSHA512)]
        for (algorithm, verifier) in cases {
            for text in [pem(pkcs1, label: "RSA PRIVATE KEY"), pem(pkcs8, label: "PRIVATE KEY")] {
                let token = try parts(JWTSigner.token(jwt(algorithm, key: text)))
                XCTAssertEqual(token.header["alg"] as? String, algorithm.rawValue)
                XCTAssertTrue(SecKeyVerifySignature(publicKey, verifier, token.input as CFData, token.signature as CFData, &error), algorithm.rawValue)
            }
        }
        XCTAssertThrowsError(try JWTSigner.token(jwt(.rs256, key: P256.Signing.PrivateKey().pemRepresentation)))
        XCTAssertThrowsError(try JWTSigner.token(jwt(.rs256, key: "-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----")))
        XCTAssertThrowsError(try JWTSigner.token(jwt(.ps256, key: "not a key")))
    }

    func testECDSATokensUseRawSignaturesOnTheMatchingCurve() throws {
        let p256 = P256.Signing.PrivateKey(), p384 = P384.Signing.PrivateKey(), p521 = P521.Signing.PrivateKey()
        var token = try parts(JWTSigner.token(jwt(.es256, key: p256.pemRepresentation))); XCTAssertEqual(token.signature.count, 64)
        XCTAssertTrue(p256.publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: token.signature), for: token.input))
        token = try parts(JWTSigner.token(jwt(.es384, key: p384.pemRepresentation))); XCTAssertEqual(token.signature.count, 96)
        XCTAssertTrue(p384.publicKey.isValidSignature(try P384.Signing.ECDSASignature(rawRepresentation: token.signature), for: token.input))
        token = try parts(JWTSigner.token(jwt(.es512, key: p521.pemRepresentation))); XCTAssertEqual(token.signature.count, 132)
        XCTAssertTrue(p521.publicKey.isValidSignature(try P521.Signing.ECDSASignature(rawRepresentation: token.signature), for: token.input))
        XCTAssertThrowsError(try JWTSigner.token(jwt(.es384, key: p256.pemRepresentation)))
    }

    func testJWTBearerIsSentInHeaderOrQueryAndRoundTripsThroughPostmanAndSync() throws {
        var auth = jwt(.hs256, secret: "{{secret}}", payload: #"{"sub":"{{user}}"}"#); auth.headerPrefix = "JWT"
        var request = APIRequest(url: "https://example.test/items"); request.auth.kind = .jwt; request.auth.jwt = auth
        let variables = ["secret": "your-256-bit-secret", "user": "ada"]
        let header = try XCTUnwrap(RequestBuilder.build(request, variables: variables).value(forHTTPHeaderField: "Authorization"))
        auth.secret = "your-256-bit-secret"; auth.payload = #"{"sub":"ada"}"#
        XCTAssertEqual(header, "JWT " + (try JWTSigner.token(auth)))
        request.auth.jwt?.inQuery = true; request.auth.jwt?.queryKey = "access"
        let url = try XCTUnwrap(RequestBuilder.build(request, variables: variables).url)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, try JWTSigner.token(auth))
        XCTAssertNil(try RequestBuilder.build(request, variables: variables).value(forHTTPHeaderField: "Authorization"))

        request.auth.jwt?.inQuery = false; request.auth.jwt?.algorithm = .es256; request.auth.jwt?.privateKey = "{{key}}"
        let workspace = Workspace(collections: [RequestCollection(name: "JWT", requests: [request])])
        let decoded = try CollectionCodec.decode(CollectionCodec.encode(workspace, format: .postman)).workspace.collections[0].requests[0].auth
        XCTAssertEqual(decoded.kind, .jwt); XCTAssertEqual(decoded.jwt, request.auth.jwt)
        let postman = #"{"info":{"name":"P"},"item":[{"name":"J","request":{"method":"GET","url":"https://x.test","auth":{"type":"jwt","jwt":[{"key":"algorithm","value":"HS512"},{"key":"isSecretBase64Encoded","value":true},{"key":"secret","value":"c2VjcmV0"},{"key":"payload","value":"{\"a\":1}"},{"key":"addTokenTo","value":"queryParam"},{"key":"queryParamKey","value":"jwt"},{"key":"header","value":{}}]}}}]}"#
        let imported = try XCTUnwrap(CollectionCodec.decode(Data(postman.utf8)).workspace.collections[0].requests[0].auth.jwt)
        XCTAssertEqual(imported.algorithm, .hs512); XCTAssertTrue(imported.secretIsBase64); XCTAssertTrue(imported.inQuery); XCTAssertEqual(imported.queryKey, "jwt"); XCTAssertEqual(imported.headerPrefix, "Bearer"); XCTAssertEqual(imported.header, "{}")

        var secrets: [String: String] = [:], signed = workspace; signed.collections[0].requests[0].auth.jwt?.privateKey = "-----BEGIN PRIVATE KEY-----private"; signed.collections[0].requests[0].auth.jwt?.secret = "shh"
        let clean = SecretPolicy.strip(signed, secrets: &secrets, files: false)
        XCTAssertEqual(clean.collections[0].requests[0].auth.jwt?.privateKey, ""); XCTAssertEqual(clean.collections[0].requests[0].auth.jwt?.secret, "")
        XCTAssertEqual(SecretPolicy.restore(clean, secrets: secrets).collections[0].requests[0].auth.jwt, signed.collections[0].requests[0].auth.jwt)
    }

    func testRedactedCodeNeverSignsOrLeaksTheToken() throws {
        var request = APIRequest(url: "https://example.test/items"); request.auth.kind = .jwt; request.auth.jwt = jwt(.hs256, secret: "your-256-bit-secret")
        let token = try JWTSigner.token(request.auth.jwt!)
        let code = try CodeGenerator.generate(request, variables: [:], language: .curl)
        XCTAssertFalse(code.contains(token)); XCTAssertTrue(code.contains("Bearer <JWT>"), code)
        XCTAssertTrue(try CodeGenerator.generate(request, variables: [:], language: .curl, redact: false).contains(token))
        request.auth.jwt?.secret = ""; request.auth.jwt?.inQuery = true; request.auth.jwt?.queryKey = "jwt"
        XCTAssertTrue(try CodeGenerator.generate(request, variables: [:], language: .curl).contains("jwt=%3CJWT%3E"))
    }
}
