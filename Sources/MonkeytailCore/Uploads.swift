import Foundation

public struct RequestFile: Codable, Equatable, Sendable {
    public var filename: String
    public var mimeType: String
    /// Native exports include bytes. External imports require choosing the file on this device.
    public var data: Data?
    public init(filename: String, mimeType: String = "application/octet-stream", data: Data? = nil) {
        self.filename = filename; self.mimeType = mimeType; self.data = data
    }
}

public struct MultipartPart: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String
    public var enabled: Bool
    public var file: RequestFile?
    public init(name: String = "", value: String = "", enabled: Bool = true, file: RequestFile? = nil) {
        self.name = name; self.value = value; self.enabled = enabled; self.file = file
    }
}

public enum MultipartEncoder {
    public static let maximumBytes = 20 * 1024 * 1024
    public static func encode(_ parts: [MultipartPart], boundary: String, variables: [String: String]) throws -> Data {
        var body = Data()
        func append(_ data: Data) throws {
            guard data.count <= maximumBytes - body.count else { throw ClientError("Upload exceeds the 20 MB limit.") }
            body.append(data)
        }
        for part in parts where part.enabled && !part.name.isEmpty {
            let name = try quoted(RequestBuilder.resolve(part.name, variables: variables))
            var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\""
            let payload: Data
            if let file = part.file {
                guard let bytes = file.data else { throw ClientError("Choose the file ‘\(file.filename)’ before sending.") }
                header += "; filename=\"\(try quoted(file.filename))\"\r\nContent-Type: \(try mime(file.mimeType))"
                payload = bytes
            } else { payload = Data(try RequestBuilder.resolve(part.value, variables: variables).utf8) }
            try append(Data((header + "\r\n\r\n").utf8)); try append(payload); try append(Data("\r\n".utf8))
        }
        try append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
    public static func mime(_ value: String) throws -> String {
        guard !value.isEmpty, value.contains("/"), !value.contains(where: { $0.isNewline || $0 == "\0" }) else { throw ClientError("Invalid file MIME type.") }
        return value
    }
    private static func quoted(_ value: String) throws -> String {
        guard !value.contains(where: { $0.isNewline || $0 == "\0" }) else { throw ClientError("Invalid multipart field name or filename.") }
        return value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
