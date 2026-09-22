import Foundation

public enum BrowserProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case chrome = "chrome150"
    case chromeAndroid = "chrome131_android"
    case firefox = "firefox147"
    case safari = "safari2601"
    case safariIOS = "safari260_ios"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .chrome: return "Chrome 150"
        case .chromeAndroid: return "Chrome 131 · Android"
        case .firefox: return "Firefox 147"
        case .safari: return "Safari 26.0.1 · Mac"
        case .safariIOS: return "Safari 26 · iOS"
        }
    }
    public static func parse(_ value: String) throws -> Self {
        if let profile = Self(rawValue: value) { return profile }
        switch value {
        case "chrome": return .chrome
        case "chrome_android": return .chromeAndroid
        case "firefox": return .firefox
        case "safari": return .safari
        case "safari_ios": return .safariIOS
        default: throw ClientError("Unsupported TLS profile: \(value). Choose Chrome, Firefox, Safari, or Safari iOS in request settings.")
        }
    }
}

public struct BrowserImpersonation: Codable, Equatable, Sendable {
    public var profile: BrowserProfile
    public var browserHeaders: Bool
    public init(profile: BrowserProfile, browserHeaders: Bool = true) {
        self.profile = profile; self.browserHeaders = browserHeaders
    }
    public static var thirdPartyNotices: String {
        guard let url = Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
