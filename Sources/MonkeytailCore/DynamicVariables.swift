import Foundation

/// Postman-compatible `{{$name}}` values. Each occurrence generates a fresh value.
public enum DynamicVariables {
    private static let firstNames = ["Ada", "Alan", "Grace", "Linus", "Margaret", "Ken", "Barbara", "Dennis", "Radia", "Tim", "Hedy", "Guido"]
    private static let lastNames = ["Lovelace", "Turing", "Hopper", "Torvalds", "Hamilton", "Thompson", "Liskov", "Ritchie", "Perlman", "Berners-Lee", "Lamarr", "Rossum"]
    private static let words = ["monkey", "tail", "banana", "river", "signal", "harbor", "orbit", "maple", "copper", "lantern", "meadow", "pixel"]
    private static let cities = ["Singapore", "Tokyo", "Lisbon", "Toronto", "Nairobi", "Oslo", "Melbourne", "Seoul", "Lima", "Dublin"]
    private static let countries = ["Singapore", "Japan", "Portugal", "Canada", "Kenya", "Norway", "Australia", "South Korea", "Peru", "Ireland"]
    private static let colors = ["red", "green", "blue", "orange", "purple", "teal", "yellow", "black", "white", "gray"]
    private static let alphanumerics = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    public static let names = ["$guid", "$randomUUID", "$timestamp", "$isoTimestamp", "$randomInt", "$randomBoolean", "$randomAlphaNumeric", "$randomHexadecimal",
                               "$randomFirstName", "$randomLastName", "$randomFullName", "$randomUserName", "$randomEmail", "$randomPassword", "$randomWord",
                               "$randomCity", "$randomCountry", "$randomColor", "$randomIP", "$randomPhoneNumber", "$randomUrl", "$randomDatePast", "$randomDateFuture"]

    public static func value(_ name: String, now: Date = Date()) -> String? {
        switch name {
        case "$guid", "$randomUUID": return UUID().uuidString.lowercased()
        case "$timestamp": return String(Int(now.timeIntervalSince1970))
        case "$isoTimestamp": return iso(now)
        case "$randomInt": return String(Int.random(in: 0...1000))
        case "$randomBoolean": return String(Bool.random())
        case "$randomAlphaNumeric": return String(alphanumerics.randomElement()!)
        case "$randomHexadecimal": return String(Int.random(in: 0...15), radix: 16)
        case "$randomFirstName": return firstNames.randomElement()!
        case "$randomLastName": return lastNames.randomElement()!
        case "$randomFullName": return firstNames.randomElement()! + " " + lastNames.randomElement()!
        case "$randomUserName": return firstNames.randomElement()!.lowercased() + "." + lastNames.randomElement()!.lowercased().replacingOccurrences(of: "-", with: "") + String(Int.random(in: 1...99))
        case "$randomEmail": return value("$randomUserName", now: now)! + "@example.com"
        case "$randomPassword": return String((0..<15).map { _ in alphanumerics.randomElement()! })
        case "$randomWord": return words.randomElement()!
        case "$randomCity": return cities.randomElement()!
        case "$randomCountry": return countries.randomElement()!
        case "$randomColor": return colors.randomElement()!
        case "$randomIP": return (0..<4).map { _ in String(Int.random(in: 1...254)) }.joined(separator: ".")
        case "$randomPhoneNumber": return String(format: "%03d-%03d-%04d", Int.random(in: 200...999), Int.random(in: 200...999), Int.random(in: 0...9999))
        case "$randomUrl": return "https://" + words.randomElement()! + ".example.com"
        case "$randomDatePast": return iso(now.addingTimeInterval(-Double.random(in: 86_400...31_536_000)))
        case "$randomDateFuture": return iso(now.addingTimeInterval(Double.random(in: 86_400...31_536_000)))
        default: return nil
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
