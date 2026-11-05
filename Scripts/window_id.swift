import CoreGraphics
// Prints the CGWindowID of an app's largest on-screen window, for `screencapture -l`.
let owner = CommandLine.arguments.dropFirst().first ?? "Monkeytail"
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
    $0[kCGWindowOwnerName as String] as? String == owner && $0[kCGWindowLayer as String] as? Int == 0
}
let area = { (w: [String: Any]) -> Double in let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]; return (b["Width"] ?? 0) * (b["Height"] ?? 0) }
if let id = windows.max(by: { area($0) < area($1) })?[kCGWindowNumber as String] { print(id) }
