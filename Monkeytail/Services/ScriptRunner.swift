import Foundation
import WebKit
import MonkeytailCore

struct ScriptResult: Decodable {
    struct Request: Decodable { var method: String; var url: String; var headers: [String: String]; var body: String }
    struct Log: Decodable { var level: String; var message: String }
    var request: Request
    var variables: [String: String]
    var logs: [Log]
}

/// Each script gets an ephemeral WebKit context. Evaluation runs outside the app process.
@MainActor
final class ScriptRunner: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ScriptResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var script = ""
    private var payload = ""
    private var executionLimit: Double = 3

    func run(_ script: String, request: APIRequest, response: APIResponse? = nil, variables: [String: String], timeout: Double = 3) async throws -> ScriptResult {
        try Task.checkCancellation()
        self.script = script
        executionLimit = timeout
        let headers = request.headers.filter(\.enabled).reduce(into: [String: String]()) { $0[$1.name] = $1.value }
        var input: [String: Any] = ["request": ["method": request.method, "url": request.url, "headers": headers, "body": request.body], "variables": variables]
        if let response {
            input["response"] = ["status": response.status, "duration": response.duration, "body": response.text, "headers": response.headers.reduce(into: [String: String]()) { $0[$1.name] = $1.value }]
        }
        payload = String(decoding: try JSONSerialization.data(withJSONObject: input), as: UTF8.self)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                let view = WKWebView(frame: .zero, configuration: config)
                view.navigationDelegate = self
                webView = view
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(ClientError("The JavaScript sandbox could not start within 10 seconds.")))
                }
                view.loadHTMLString("<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline'; connect-src 'none'; form-action 'none'\"></head><body></body></html>", baseURL: nil)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil else { return }
        timeoutTask?.cancel()
        let limit = executionLimit
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled else { return }
            self?.finish(.failure(ClientError("JavaScript exceeded its \(Int(limit))-second time limit.")))
        }
        let program = #"""
        const input = JSON.parse(payload);
        // randomUUID is secure-context-only in WebKit; getRandomValues is also
        // available to this network-isolated about:blank document.
        if (typeof globalThis.crypto.randomUUID !== 'function') {
          globalThis.crypto.randomUUID = () => {
            const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16));
            bytes[6] = (bytes[6] & 15) | 64;
            bytes[8] = (bytes[8] & 63) | 128;
            const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
            return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
          };
        }
        const request = input.request;
        const vars = {...input.variables};
        const logs = [];
        const stringify = x => typeof x === 'string' ? x : JSON.stringify(x);
        const log = (level, values) => { if (logs.length < 200) logs.push({level, message: values.map(stringify).join(' ').slice(0, 10000)}); };
        const console = {log: (...x) => log('info', x), warn: (...x) => log('warning', x), error: (...x) => log('error', x)};
        const environment = {get: k => vars[k], set: (k,v) => {vars[k] = String(v);}, unset: k => {delete vars[k];}};
        const response = input.response ? {...input.response, code: input.response.status, json: () => JSON.parse(input.response.body), text: () => input.response.body} : undefined;
        const assert = (condition, message = 'Assertion failed') => {if (!condition) throw new Error(message);};
        const test = (name, fn) => {try {const result = fn(); if (result && typeof result.then === 'function') throw new Error('Use synchronous test callbacks'); log('pass', [name]);} catch(e) {log('fail', [name + ': ' + e.message]);}};
        const expect = actual => ({to: {equal: expected => assert(actual === expected, `Expected ${actual} to equal ${expected}`), eql: expected => assert(JSON.stringify(actual) === JSON.stringify(expected), 'Values differ')}});
        const pm = {environment, variables: environment, request, response, test, expect};
        if (response) response.to = {have: {status: status => assert(response.status === status, `Expected HTTP ${status}, received ${response.status}`)}};
        Object.defineProperty(request.headers, 'upsert', {value: field => {request.headers[field.key] = String(field.value);}});
        Object.defineProperty(request.headers, 'add', {value: field => {request.headers[field.key] = String(field.value);}});
        Object.defineProperty(request.headers, 'remove', {value: key => {delete request.headers[key];}});
        """# + "\n" + script + #"""

        return JSON.stringify({request, variables: vars, logs});
        """#
        webView.callAsyncJavaScript(program, arguments: ["payload": payload], in: nil, in: .page) { [weak self] result in
            switch result {
            case .success(let value):
                guard let text = value as? String else { self?.finish(.failure(ClientError("The script did not produce a valid result. Avoid top-level return statements."))); return }
                do { self?.finish(.success(try JSONDecoder().decode(ScriptResult.self, from: Data(text.utf8)))) }
                catch { self?.finish(.failure(ClientError("Scripts must leave request fields and environment values as strings."))) }
            case .failure(let error):
                let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                self?.finish(.failure(ClientError("JavaScript: \(detail)")))
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(ClientError("The JavaScript process terminated."))) }
    private func finish(_ result: Result<ScriptResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView = nil
        continuation.resume(with: result)
    }
}
