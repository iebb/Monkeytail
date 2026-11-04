import Foundation
import WebKit
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct ScriptResult: Decodable {
    struct Request: Decodable { var method: String; var url: String; var headers: [String: String]; var body: String }
    struct Log: Decodable { var level: String; var message: String }
    struct Next: Decodable { var name: String?; var stop: Bool? }
    var request: Request
    var variables: [String: String]
    var globals: [String: String]?
    var collectionVariables: [String: String]?
    /// `pm.variables.set` values: this send and the rest of a collection run, never saved.
    var locals: [String: String]?
    var logs: [Log]
    var next: Next?
    var skip: Bool?
    var directive: RunnerDirective? {
        guard let next else { return nil }
        if next.stop == true { return .stop }
        return next.name.map(RunnerDirective.jump)
    }
}

/// Collection-run details exposed as `pm.info` and `pm.iterationData`.
struct ScriptContext {
    var iterationData: [String: String] = [:]
    var iteration = 0
    var iterationCount = 1
    var globals: [String: String] = [:]
    var collectionVariables: [String: String] = [:]
    /// `pm.cookies`: cookies for the request URL.
    var cookies: [StoredCookie] = []
    /// Enables `pm.sendRequest` through this proxy. nil keeps the script offline.
    var proxy: ProxySettings?
}

/// Each script gets an ephemeral WebKit context. Evaluation runs outside the app process.
/// The only network path is the bounded native `pm.sendRequest` bridge; fetch and XHR stay blocked.
@MainActor
final class ScriptRunner: NSObject, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    static let maximumSentRequests = 10
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ScriptResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var script = ""
    private var payload = ""
    private var executionLimit: Double = 3
    private var proxy: ProxySettings?
    private var sentRequests = 0
    private var inFlight = 0

    func run(_ script: String, request: APIRequest, response: APIResponse? = nil, variables: [String: String], context: ScriptContext = ScriptContext(), timeout: Double = 3) async throws -> ScriptResult {
        try Task.checkCancellation()
        self.script = script
        executionLimit = timeout
        proxy = context.proxy; sentRequests = 0; inFlight = 0
        let headers = request.headers.filter(\.enabled).reduce(into: [String: String]()) { $0[$1.name] = $1.value }
        var input: [String: Any] = ["request": ["method": request.method, "url": request.url, "headers": headers, "body": request.body], "variables": variables,
                                    "iterationData": context.iterationData, "globals": context.globals, "collectionVariables": context.collectionVariables,
                                    "cookies": context.cookies.map { cookie -> [String: Any] in
                                        var item: [String: Any] = ["name": cookie.name, "value": cookie.value, "domain": cookie.domain, "path": cookie.path, "secure": cookie.secure, "httpOnly": cookie.httpOnly, "hostOnly": cookie.hostOnly]
                                        if let expires = cookie.expires { item["expires"] = ISO8601DateFormatter().string(from: expires) }
                                        return item
                                    },
                                    "info": ["requestName": request.name, "requestId": request.id.uuidString, "iteration": context.iteration, "iterationCount": context.iterationCount, "eventName": response == nil ? "prerequest" : "test"]]
        if let response {
            input["response"] = ["status": response.status, "duration": response.duration, "body": response.text, "headers": response.headers.reduce(into: [String: String]()) { $0[$1.name] = $1.value }]
        }
        payload = String(decoding: try JSONSerialization.data(withJSONObject: input), as: UTF8.self)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                if proxy != nil { config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "sendRequest") }
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
        startExecutionTimer()
        webView.callAsyncJavaScript(ScriptLibraries.source + Self.harness + "\nawait (async () => {\n" + script + "\n})();\n" + Self.epilogue, arguments: ["payload": payload], in: nil, in: .page) { [weak self] result in
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

    /// The deadline covers JavaScript execution; it pauses while pm.sendRequest calls are in flight.
    private func startExecutionTimer() {
        timeoutTask?.cancel()
        let limit = executionLimit
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled else { return }
            self?.finish(.failure(ClientError("JavaScript exceeded its \(Int(limit))-second time limit.")))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard continuation != nil, let proxy else { replyHandler(nil, "pm.sendRequest is unavailable."); return }
        guard sentRequests < Self.maximumSentRequests else { replyHandler(nil, "Scripts can send at most \(Self.maximumSentRequests) requests."); return }
        let request: URLRequest
        do { request = try Self.urlRequest(message.body) } catch { replyHandler(nil, error.localizedDescription); return }
        sentRequests += 1; inFlight += 1
        timeoutTask?.cancel()
        Task { [weak self] in
            do {
                let response = try await HTTPClient().send(request, proxy: proxy)
                replyHandler(["code": response.status, "body": response.text, "responseTime": Int(response.duration * 1000),
                              "headers": response.headers.map { ["key": $0.name, "value": $0.value] }], nil)
            } catch { replyHandler(nil, error.localizedDescription) }
            guard let self else { return }
            inFlight -= 1
            if inFlight == 0, continuation != nil { startExecutionTimer() }
        }
    }

    private static func urlRequest(_ body: Any) throws -> URLRequest {
        guard let spec = body as? [String: Any], let text = spec["url"] as? String, let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { throw ClientError("pm.sendRequest needs a complete http:// or https:// URL.") }
        let method = (spec["method"] as? String ?? "GET").uppercased()
        guard method.range(of: #"^[A-Z0-9!#$%&'*+.^_`|~-]+$"#, options: .regularExpression) != nil else { throw ClientError("pm.sendRequest has an invalid method.") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        for (name, value) in spec["headers"] as? [String: String] ?? [:] {
            guard !name.isEmpty, !(name + value).contains(where: { $0 == "\r" || $0 == "\n" }) else { throw ClientError("pm.sendRequest has an invalid header.") }
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let text = spec["body"] as? String, !text.isEmpty {
            guard text.utf8.count <= MultipartEncoder.maximumBytes else { throw ClientError("Upload exceeds the 20 MB limit.") }
            request.httpBody = Data(text.utf8)
        }
        return request
    }

    private static let harness = #"""
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
        const environment = {get: k => vars[k], has: k => Object.prototype.hasOwnProperty.call(vars, k), set: (k,v) => {vars[k] = String(v);}, unset: k => {delete vars[k];},
          replaceIn: s => String(s).replace(/\{\{\s*([\w.\-]+)\s*\}\}/g, (m, k) => Object.prototype.hasOwnProperty.call(vars, k) ? vars[k] : m), toObject: () => ({...vars})};
        const __globals = {...input.globals};
        const globals = {get: k => __globals[k], has: k => Object.prototype.hasOwnProperty.call(__globals, k), set: (k,v) => {__globals[k] = String(v);}, unset: k => {delete __globals[k];},
          clear: () => {for (const k of Object.keys(__globals)) delete __globals[k];}, replaceIn: environment.replaceIn, toObject: () => ({...__globals})};
        const __locals = {};
        const localVariables = {get: k => __has(__locals, k) ? __locals[k] : vars[k], has: k => __has(__locals, k) || __has(vars, k), set: (k,v) => {__locals[k] = String(v);}, unset: k => {delete __locals[k];},
          replaceIn: s => String(s).replace(/\{\{\s*([\w.\-]+)\s*\}\}/g, (m, k) => __has(__locals, k) ? __locals[k] : __has(vars, k) ? vars[k] : m), toObject: () => ({...vars, ...__locals})};
        const __collection = {...input.collectionVariables};
        const collectionVariables = {get: k => __collection[k], has: k => Object.prototype.hasOwnProperty.call(__collection, k), set: (k,v) => {__collection[k] = String(v);}, unset: k => {delete __collection[k];},
          clear: () => {for (const k of Object.keys(__collection)) delete __collection[k];}, replaceIn: environment.replaceIn, toObject: () => ({...__collection})};
        const response = input.response ? {...input.response, code: input.response.status, responseTime: Math.round(input.response.duration * 1000), json: () => JSON.parse(input.response.body), text: () => input.response.body} : undefined;
        const assert = (condition, message = 'Assertion failed') => {if (!condition) throw new Error(message);};
        const __pending = [];
        const test = (name, fn) => {
          try {
            const result = fn();
            if (result && typeof result.then === 'function') __pending.push(result.then(() => log('pass', [name]), e => log('fail', [name + ': ' + (e && e.message || e)])));
            else log('pass', [name]);
          } catch(e) {log('fail', [name + ': ' + e.message]);}
        };
        test.skip = name => log('info', ['Skipped test: ' + name]);
        const __has = (o, k) => o !== null && o !== undefined && Object.prototype.hasOwnProperty.call(Object(o), k);
        const __show = v => { try { return typeof v === 'function' ? '[function]' : v === undefined ? 'undefined' : JSON.stringify(v); } catch { return String(v); } };
        const __type = v => v === null ? 'null' : Array.isArray(v) ? 'array' : v instanceof RegExp ? 'regexp' : v instanceof Date ? 'date' : typeof v;
        const __equal = (a, b) => {
          if (a === b || (Number.isNaN(a) && Number.isNaN(b))) return true;
          if (typeof a !== 'object' || typeof b !== 'object' || a === null || b === null || Array.isArray(a) !== Array.isArray(b)) return false;
          const ka = Object.keys(a), kb = Object.keys(b);
          return ka.length === kb.length && ka.every(k => __has(b, k) && __equal(a[k], b[k]));
        };
        // A Chai BDD subset covering the assertions common in Postman tests.
        const expect = (actual, prefix) => {
          const flags = {not: false, deep: false, any: false};
          const chain = {};
          const check = (ok, message, negated) => {
            if (flags.not ? ok : !ok) throw new Error((prefix ? prefix + ': ' : '') + (flags.not ? negated : message));
            return chain;
          };
          const getter = (name, fn) => Object.defineProperty(chain, name, {get: fn});
          for (const word of ['to', 'be', 'been', 'is', 'that', 'which', 'and', 'has', 'have', 'with', 'at', 'of', 'same', 'but', 'does', 'still', 'also', 'own', 'nested', 'ordered']) getter(word, () => chain);
          getter('not', () => { flags.not = !flags.not; return chain; });
          getter('deep', () => { flags.deep = true; return chain; });
          getter('all', () => { flags.any = false; return chain; });
          getter('any', () => { flags.any = true; return chain; });
          const a = __show(actual);
          getter('ok', () => check(!!actual, `expected ${a} to be truthy`, `expected ${a} to be falsy`));
          getter('true', () => check(actual === true, `expected ${a} to be true`, `expected ${a} not to be true`));
          getter('false', () => check(actual === false, `expected ${a} to be false`, `expected ${a} not to be false`));
          getter('null', () => check(actual === null, `expected ${a} to be null`, `expected ${a} not to be null`));
          getter('undefined', () => check(actual === undefined, `expected ${a} to be undefined`, `expected ${a} not to be undefined`));
          getter('NaN', () => check(Number.isNaN(actual), `expected ${a} to be NaN`, `expected ${a} not to be NaN`));
          getter('exist', () => check(actual !== null && actual !== undefined, `expected ${a} to exist`, `expected ${a} not to exist`));
          getter('empty', () => check(actual != null && (typeof actual === 'string' || Array.isArray(actual) ? actual.length === 0 : Object.keys(actual).length === 0), `expected ${a} to be empty`, `expected ${a} not to be empty`));
          const equal = expected => check(flags.deep ? __equal(actual, expected) : actual === expected, `expected ${a} to equal ${__show(expected)}`, `expected ${a} not to equal ${__show(expected)}`);
          const eql = expected => check(__equal(actual, expected), `expected ${a} to deeply equal ${__show(expected)}`, `expected ${a} not to deeply equal ${__show(expected)}`);
          const type = name => check(__type(actual) === String(name).toLowerCase(), `expected ${a} to be ${name}`, `expected ${a} not to be ${name}`);
          const include = value => {
            let ok;
            if (typeof actual === 'string') ok = actual.includes(value);
            else if (Array.isArray(actual)) ok = actual.some(item => flags.deep || typeof value === 'object' ? __equal(item, value) : item === value);
            else if (actual && typeof actual === 'object' && value && typeof value === 'object') ok = Object.keys(value).every(k => __equal(actual[k], value[k]));
            else ok = false;
            return check(ok, `expected ${a} to include ${__show(value)}`, `expected ${a} not to include ${__show(value)}`);
          };
          const compare = (ok, word, n) => check(ok, `expected ${a} to be ${word} ${n}`, `expected ${a} not to be ${word} ${n}`);
          const length = n => check(actual != null && actual.length === n, `expected ${a} to have length ${n}`, `expected ${a} not to have length ${n}`);
          const keys = (...names) => {
            const wanted = names.length === 1 && Array.isArray(names[0]) ? names[0] : names.length === 1 && names[0] && typeof names[0] === 'object' ? Object.keys(names[0]) : names;
            const present = actual && typeof actual === 'object' ? Object.keys(actual) : [];
            const ok = flags.any ? wanted.some(k => present.includes(k)) : wanted.length === present.length && wanted.every(k => present.includes(k));
            return check(ok, `expected ${a} to have keys ${__show(wanted)}`, `expected ${a} not to have keys ${__show(wanted)}`);
          };
          Object.assign(chain, {
            equal, equals: equal, eq: equal, eql, eqls: eql, a: type, an: type, include, includes: include, contain: include, contains: include,
            above: n => compare(actual > n, 'above', n), gt: n => compare(actual > n, 'above', n), greaterThan: n => compare(actual > n, 'above', n),
            below: n => compare(actual < n, 'below', n), lt: n => compare(actual < n, 'below', n), lessThan: n => compare(actual < n, 'below', n),
            least: n => compare(actual >= n, 'at least', n), gte: n => compare(actual >= n, 'at least', n),
            most: n => compare(actual <= n, 'at most', n), lte: n => compare(actual <= n, 'at most', n),
            within: (low, high) => compare(actual >= low && actual <= high, 'within', `${low}..${high}`),
            lengthOf: length, length,
            match: re => check(re.test(String(actual)), `expected ${a} to match ${re}`, `expected ${a} not to match ${re}`),
            string: s => check(String(actual).includes(s), `expected ${a} to contain ${__show(s)}`, `expected ${a} not to contain ${__show(s)}`),
            oneOf: list => check(list.some(item => __equal(item, actual)), `expected ${a} to be one of ${__show(list)}`, `expected ${a} not to be one of ${__show(list)}`),
            members: list => check(Array.isArray(actual) && actual.length === list.length && list.every(item => actual.some(x => __equal(x, item))), `expected ${a} to have members ${__show(list)}`, `expected ${a} not to have members ${__show(list)}`),
            keys, key: keys,
            instanceOf: ctor => check(actual instanceof ctor, `expected ${a} to be an instance of ${ctor.name}`, `expected ${a} not to be an instance of ${ctor.name}`),
            property: function(name, value) {
              const exists = actual !== null && actual !== undefined && name in Object(actual);
              if (arguments.length > 1) return check(exists && __equal(actual[name], value), `expected ${a} to have property ${__show(name)} of ${__show(value)}`, `expected ${a} not to have property ${__show(name)} of ${__show(value)}`);
              check(exists, `expected ${a} to have property ${__show(name)}`, `expected ${a} not to have property ${__show(name)}`);
              return flags.not ? chain : expect(actual[name], prefix);
            }
          });
          return chain;
        };
        expect.fail = message => { throw new Error(message || 'expect.fail()'); };
        const __headers = dict => {
          const find = name => Object.keys(dict).find(k => k.toLowerCase() === String(name).toLowerCase());
          const helpers = {get: name => { const k = find(name); return k === undefined ? undefined : dict[k]; },
            has: (name, value) => { const k = find(name); return k !== undefined && (value === undefined || dict[k] === String(value)); }, toObject: () => ({...dict})};
          for (const [name, fn] of Object.entries(helpers)) Object.defineProperty(dict, name, {value: fn, configurable: true});
          return dict;
        };
        const __listHeaders = list => __headers((list || []).reduce((o, h) => { o[h.key] = h.value; return o; }, {}));
        if (response) {
          __headers(response.headers);
          response.responseSize = response.body.length;
          const assertions = negate => {
            const status = response.status, type = response.headers.get('content-type') || '';
            const verify = (ok, message) => { if (negate ? ok : !ok) throw new Error((negate ? 'Not expected: ' : 'Expected ') + message + `, received HTTP ${status}`); };
            const be = {};
            const statuses = {ok: s => s === 200, success: s => s >= 200 && s < 300, accepted: s => s === 202, badRequest: s => s === 400, unauthorized: s => s === 401, unauthorised: s => s === 401,
              forbidden: s => s === 403, notFound: s => s === 404, rateLimited: s => s === 429, error: s => s >= 400, clientError: s => s >= 400 && s < 500, serverError: s => s >= 500, info: s => s < 200, redirection: s => s >= 300 && s < 400};
            for (const [name, predicate] of Object.entries(statuses)) Object.defineProperty(be, name, {get: () => verify(predicate(status), `response to be ${name}`)});
            Object.defineProperty(be, 'json', {get: () => { let parsed = true; try { JSON.parse(response.body); } catch { parsed = false; } verify(type.includes('json') && parsed, 'a JSON response'); }});
            Object.defineProperty(be, 'withBody', {get: () => verify(response.body.length > 0, 'a response body')});
            const jsonValue = path => String(path).split('.').filter(Boolean).reduce((value, key) => value == null ? undefined : value[key], response.json());
            const have = {
              status: code => verify(code === status || (typeof code === 'string' && Number(code) === status), `HTTP ${code}`),
              header: (name, value) => verify(response.headers.has(name, value), value === undefined ? `header ${name}` : `header ${name}: ${value}`),
              body: value => verify(value === undefined ? response.body.length > 0 : value instanceof RegExp ? value.test(response.body) : response.body === String(value), value === undefined ? 'a response body' : `body ${__show(value)}`),
              jsonBody: function(path, value) {
                let ok;
                try { ok = path === undefined || (typeof path === 'object' ? __equal(response.json(), path) : arguments.length > 1 ? __equal(jsonValue(path), value) : jsonValue(path) !== undefined); } catch { ok = false; }
                verify(ok, path === undefined ? 'a JSON body' : `JSON body ${__show(path)}${arguments.length > 1 ? ' = ' + __show(value) : ''}`);
              },
              responseTime: limit => verify(response.responseTime <= limit, `a response time of at most ${limit} ms`)
            };
            return {have, be, get not() { return assertions(!negate); }, get to() { return this; }};
          };
          response.to = assertions(false);
        }
        const __toHeaders = h => {
          const out = {};
          if (Array.isArray(h)) h.forEach(x => { if (x && !x.disabled) out[x.key] = String(x.value ?? ''); });
          else if (typeof h === 'string') h.split('\n').forEach(line => { const i = line.indexOf(':'); if (i > 0) out[line.slice(0, i).trim()] = line.slice(i + 1).trim(); });
          else if (h) Object.entries(h).forEach(([k, v]) => { out[k] = String(v); });
          return out;
        };
        const __toBody = (b, headers) => {
          const setType = value => { if (!Object.keys(headers).some(k => k.toLowerCase() === 'content-type')) headers['Content-Type'] = value; };
          if (b === undefined || b === null) return '';
          if (typeof b === 'string') return b;
          switch (b.mode) {
            case 'raw': return typeof b.raw === 'string' ? b.raw : JSON.stringify(b.raw ?? '');
            case 'urlencoded': setType('application/x-www-form-urlencoded'); return (b.urlencoded || []).filter(x => !x.disabled).map(x => encodeURIComponent(x.key) + '=' + encodeURIComponent(x.value ?? '')).join('&');
            case 'graphql': setType('application/json'); return JSON.stringify(b.graphql ?? {});
            default: throw new Error('pm.sendRequest supports raw, urlencoded, and graphql bodies.');
          }
        };
        const __sendRequest = (spec, callback) => {
          const bridge = globalThis.webkit && webkit.messageHandlers && webkit.messageHandlers.sendRequest;
          let sent;
          try {
            if (!bridge) throw new Error('pm.sendRequest is unavailable in this script.');
            const options = typeof spec === 'string' ? {url: spec} : (spec || {});
            const headers = __toHeaders(options.header ?? options.headers);
            const body = __toBody(options.body, headers);
            sent = bridge.postMessage({url: String(options.url ?? ''), method: String(options.method || 'GET'), headers, body}).then(r => {
              const text = String(r.body ?? '');
              return {code: r.code, status: r.code, responseTime: r.responseTime, responseSize: text.length, headers: __listHeaders(r.headers), body: text, text: () => text, json: () => JSON.parse(text)};
            }, e => { throw new Error(String(e && e.message || e)); });
          } catch (e) { sent = Promise.reject(e); }
          const settled = sent.then(res => { if (callback) callback(null, res); return res; }, err => { if (callback) callback(err, null); else throw err; });
          __pending.push(settled.catch(e => log('error', ['pm.sendRequest: ' + e.message])));
          return settled;
        };
        const __iterationData = Object.freeze({...input.iterationData});
        let __next = null, __skip = false;
        const __setNextRequest = name => {__next = name === null ? {stop: true} : {name: String(name)};};
        const __cookieItems = (input.cookies || []).map(c => Object.freeze({...c}));
        const cookies = {get: n => __cookieItems.find(c => c.name === n)?.value, has: (n, v) => __cookieItems.some(c => c.name === n && (v === undefined || c.value === v)), one: n => __cookieItems.find(c => c.name === n),
          all: () => [...__cookieItems], count: () => __cookieItems.length, idx: i => __cookieItems[i], each: f => __cookieItems.forEach(f), filter: f => __cookieItems.filter(f), find: f => __cookieItems.find(f), map: f => __cookieItems.map(f),
          toObject: () => __cookieItems.reduce((o, c) => { if (!(c.name in o)) o[c.name] = c.value; return o; }, {}),
          jar: () => { throw new Error('pm.cookies.jar() is unavailable. Turn on the cookie jar for this request instead.'); }};
        const pm = {environment, variables: localVariables, globals, collectionVariables, request, response, cookies, test, expect, sendRequest: __sendRequest,
          execution: {setNextRequest: __setNextRequest, skipRequest: () => {__skip = true;}}, info: Object.freeze({...input.info}),
          iterationData: {get: k => __iterationData[k], has: k => Object.prototype.hasOwnProperty.call(__iterationData, k), toObject: () => ({...__iterationData})}};
        // Legacy Postman sandbox globals.
        const postman = {setNextRequest: __setNextRequest, getEnvironmentVariable: environment.get, setEnvironmentVariable: environment.set, clearEnvironmentVariable: environment.unset,
          getGlobalVariable: globals.get, setGlobalVariable: globals.set, clearGlobalVariable: globals.unset, getVariable: environment.get, getResponseCookie: cookies.one};
        // Script APIs of other clients, so imported collections run unchanged.
        const insomnia = pm;
        const __parsed = () => { try { return JSON.parse(response.body); } catch { return response.body; } };
        const __find = name => Object.keys(request.headers).find(k => k.toLowerCase() === String(name).toLowerCase());
        const bru = {getVar: localVariables.get, setVar: localVariables.set, hasVar: localVariables.has, deleteVar: localVariables.unset, getRequestVar: localVariables.get, getFolderVar: localVariables.get,
          getEnvVar: environment.get, setEnvVar: (k, v) => environment.set(k, v), hasEnvVar: environment.has, deleteEnvVar: environment.unset, getGlobalEnvVar: globals.get, setGlobalEnvVar: globals.set,
          getCollectionVar: collectionVariables.get, getProcessEnv: () => undefined, getEnvName: () => undefined, interpolate: localVariables.replaceIn, setNextRequest: __setNextRequest,
          sleep: ms => new Promise(done => setTimeout(done, Math.min(Number(ms) || 0, 2000))), runner: {setNextRequest: __setNextRequest, skipRequest: () => {__skip = true;}, stopExecution: () => __setNextRequest(null)}};
        const req = {get url() { return request.url; }, get method() { return request.method; }, get headers() { return request.headers; }, get body() { return request.body; },
          getUrl: () => request.url, setUrl: u => {request.url = String(u);}, getMethod: () => request.method, setMethod: m => {request.method = String(m).toUpperCase();},
          getHeader: n => { const k = __find(n); return k === undefined ? undefined : request.headers[k]; }, getHeaders: () => ({...request.headers}),
          setHeader: (n, v) => { const k = __find(n); if (k !== undefined) delete request.headers[k]; request.headers[n] = String(v); }, deleteHeader: n => { const k = __find(n); if (k !== undefined) delete request.headers[k]; },
          setHeaders: h => { for (const k of Object.keys(request.headers)) delete request.headers[k]; Object.entries(h || {}).forEach(([k, v]) => {request.headers[k] = String(v);}); },
          getBody: () => { try { return JSON.parse(request.body); } catch { return request.body; } }, setBody: b => {request.body = typeof b === 'string' ? b : JSON.stringify(b);}, getName: () => pm.info.requestName};
        const res = response ? {status: response.status, statusText: response.statusText, headers: response.headers, body: __parsed(), responseTime: response.responseTime,
          getStatus: () => response.status, getStatusText: () => response.statusText, getHeader: n => response.headers.get(n), getHeaders: () => response.headers.toObject(), getBody: __parsed,
          getResponseTime: () => response.responseTime, getUrl: () => request.url} : undefined;
        const __jest = (actual, negate = false) => {
          const check = (ok, message) => { if (negate ? ok : !ok) throw new Error((negate ? 'Expected not ' : 'Expected ') + message); };
          const level = (low, name) => () => check(Number(actual) >= low && Number(actual) < low + 100, `${__show(actual)} to be ${name}`);
          return {toBe: v => check(actual === v, `${__show(actual)} to be ${__show(v)}`), toEqual: v => check(__equal(actual, v), `${__show(actual)} to equal ${__show(v)}`),
            toBeLevel2xx: level(200, '2xx'), toBeLevel3xx: level(300, '3xx'), toBeLevel4xx: level(400, '4xx'), toBeLevel5xx: level(500, '5xx'),
            toBeType: t => check(typeof actual === t, `${__show(actual)} to be type ${t}`), toHaveLength: n => check(actual != null && actual.length === n, `${__show(actual)} to have length ${n}`),
            toInclude: v => check(actual != null && actual.includes(v), `${__show(actual)} to include ${__show(v)}`), get not() { return __jest(actual, !negate); }};
        };
        const __hoppEnv = {get: environment.get, getRaw: environment.get, getResolve: k => environment.replaceIn(environment.get(k) ?? ''), resolve: environment.replaceIn, set: environment.set, unset: environment.unset};
        const __hoppResponse = response ? {status: response.status, statusCode: response.status, body: __parsed(), headers: Object.entries(response.headers.toObject()).map(([key, value]) => ({key, value})),
          responseTime: response.responseTime, text: () => response.body, json: () => response.json(), asText: () => response.body, asJSON: () => response.json()} : undefined;
        const pw = {env: __hoppEnv, test, expect: v => __jest(v), response: __hoppResponse};
        const hopp = {env: {...__hoppEnv, active: __hoppEnv, global: {get: globals.get, set: globals.set, unset: globals.unset}}, test, expect, response: __hoppResponse, request};
        const tc = {getVar: k => localVariables.get(k), setVar: (k, v) => environment.set(k, v), request, test: (name, value) => test(name, () => { if ((typeof value === 'function' ? value() : value) === false) throw new Error('returned false'); }),
          response: response ? {status: response.status, headers: response.headers.toObject(), text: response.body, get json() { return __parsed(); }, time: response.responseTime} : undefined,
          check: (name, read, action, expected) => test(name, () => {
            const actual = read(), number = Number(expected), text = actual === undefined || actual === null ? '' : typeof actual === 'object' ? JSON.stringify(actual) : String(actual);
            const ok = {equal: text == expected, notequal: text != expected, contains: text.includes(expected), notcontains: !text.includes(expected), '<': Number(actual) < number, '<=': Number(actual) <= number,
              '>': Number(actual) > number, '>=': Number(actual) >= number, istype: __type(actual) === String(expected).toLowerCase(), count: actual != null && actual.length === number,
              exists: actual !== undefined, regex: new RegExp(expected).test(text), isjson: (() => { try { JSON.parse(response.body); return true; } catch { return false; } })()}[action];
            if (ok === undefined) throw new Error('Unsupported Thunder Client test action ' + action);
            if (!ok) throw new Error(`expected ${text} ${action} ${expected}`);
          })};
        const __http = {client: {global: {get: globals.get, set: globals.set, clear: globals.unset, clearAll: globals.clear, isEmpty: () => Object.keys(__globals).length === 0},
            test, assert: (condition, message) => { if (!condition) throw new Error(message || 'Assertion failed'); }, log: (...x) => log('info', x), exit: () => { throw {__exit: true}; }},
          request: {variables: {get: localVariables.get, set: localVariables.set}, environment: {get: environment.get}, url: () => request.url, method: request.method, headers: request.headers, body: () => request.body},
          response: response ? {status: response.status, body: __parsed(), contentType: {mimeType: (response.headers.get('content-type') || '').split(';')[0].trim(), charset: ((response.headers.get('content-type') || '').match(/charset=([^;]+)/) || [])[1]},
            headers: {valueOf: n => response.headers.get(n) ?? null, valuesOf: n => response.headers.has(n) ? [response.headers.get(n)] : []}} : undefined};
        const tests = {};
        const responseCookies = response ? cookies.all() : undefined;
        const responseBody = response ? response.body : undefined, responseCode = response ? {code: response.status} : undefined;
        const responseTime = response ? response.responseTime : undefined, responseHeaders = response ? response.headers.toObject() : undefined;
        const data = input.iterationData, iteration = input.info.iteration;
        __headers(request.headers);
        Object.defineProperty(request.headers, 'upsert', {value: field => {request.headers[field.key] = String(field.value);}});
        Object.defineProperty(request.headers, 'add', {value: field => {request.headers[field.key] = String(field.value);}});
        Object.defineProperty(request.headers, 'remove', {value: key => {delete request.headers[key];}});
        """#

    private static let epilogue = #"""
        while (__pending.length) await Promise.allSettled(__pending.splice(0));
        for (const [name, passed] of Object.entries(tests)) log(passed ? 'pass' : 'fail', [name]);
        return JSON.stringify({request, variables: vars, globals: __globals, collectionVariables: __collection, locals: __locals, logs, next: __next, skip: __skip});
        """#

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(ClientError("The JavaScript process terminated."))) }
    private func finish(_ result: Result<ScriptResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView = nil
        continuation.resume(with: result)
    }
}
