import Foundation
import AuthenticationServices
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor final class OAuthAuthorizer: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func authorize(_ config: OAuthConfiguration, proxy: ProxySettings) async throws -> OAuthConfiguration {
        if config.grant == .clientCredentials { return try await exchange(config, request: OAuthFlow.tokenRequest(config), proxy: proxy) }
        let verifier = try OAuthFlow.random(), state = try OAuthFlow.random(), url = try OAuthFlow.authorizationURL(config, state: state, verifier: verifier)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "monkeytail") { callback, error in
                if let callback { continuation.resume(returning: callback) } else { continuation.resume(throwing: error ?? ClientError("API authorization was cancelled.")) }
            }
            session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = true; self.session = session
            if !session.start() { self.session = nil; continuation.resume(throwing: ClientError("Could not open API authorization.")) }
        }
        defer { session = nil }
        let code = try OAuthFlow.code(from: callback, config: config, state: state)
        return try await exchange(config, request: OAuthFlow.tokenRequest(config, code: code, verifier: verifier), proxy: proxy)
    }
    func refresh(_ config: OAuthConfiguration, proxy: ProxySettings) async throws -> OAuthConfiguration {
        try await exchange(config, request: OAuthFlow.tokenRequest(config, refresh: true), proxy: proxy)
    }
    private func exchange(_ config: OAuthConfiguration, request: URLRequest, proxy: ProxySettings) async throws -> OAuthConfiguration {
        let response = try await HTTPClient(followRedirects: false).send(request, proxy: proxy)
        return try OAuthFlow.apply(response, to: config)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
        #else
        return UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? UIWindow()
        #endif
    }
}
