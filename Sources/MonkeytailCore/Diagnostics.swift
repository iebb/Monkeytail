import Foundation

public struct SentRequest: Codable, Equatable, Sendable {
    public var method: String
    public var url: String
    public var headers: [Field]
    public var body: Data
    public var bodyBytes: Int
    public init(_ request: URLRequest, headers: [Field]? = nil) {
        method = request.httpMethod ?? "GET"; url = request.url?.absoluteString ?? ""
        self.headers = headers ?? (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }.map { Field($0.key, $0.value) }
        bodyBytes = request.httpBody?.count ?? 0
        body = Data((request.httpBody ?? Data()).prefix(1024 * 1024))
    }
}

public struct HTTPTransaction: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var request: SentRequest
    public var status: Int
    public var dns: Double?
    public var connect: Double?
    public var tls: Double?
    public var upload: Double?
    public var wait: Double?
    public var download: Double?
    public var total: Double?
    public var protocolName: String?
    public var remoteAddress: String?
    public var proxy: Bool
    public var reusedConnection: Bool
    public init(request: SentRequest, status: Int, dns: Double? = nil, connect: Double? = nil, tls: Double? = nil, upload: Double? = nil, wait: Double? = nil, download: Double? = nil, total: Double? = nil, protocolName: String? = nil, remoteAddress: String? = nil, proxy: Bool = false, reusedConnection: Bool = false) {
        self.request = request; self.status = status; self.dns = dns; self.connect = connect; self.tls = tls; self.upload = upload; self.wait = wait; self.download = download; self.total = total; self.protocolName = protocolName; self.remoteAddress = remoteAddress; self.proxy = proxy; self.reusedConnection = reusedConnection
    }
}
public struct RequestDiagnostics: Codable, Equatable, Sendable {
    public var transport: String
    public var transactions: [HTTPTransaction]
    public init(transport: String, transactions: [HTTPTransaction]) { self.transport = transport; self.transactions = transactions }
}
