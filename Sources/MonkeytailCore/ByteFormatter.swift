import Foundation

public enum ByteFormatter {
    public static func row(_ bytes: ArraySlice<UInt8>, offset: Int, width: Int, binary: Bool = false) -> String {
        let values = bytes.map { byte in
            binary ? String(repeating: "0", count: 8 - String(byte, radix: 2).count) + String(byte, radix: 2) : String(format: "%02X", byte)
        }.joined(separator: " ")
        let cellWidth = binary ? 8 : 2
        let padding = String(repeating: " ", count: max(0, width * (cellWidth + 1) - 1 - values.count))
        let ascii = bytes.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
        return String(format: "%08X", offset) + "  " + values + padding + "  " + ascii
    }

    public static func dump(_ bytes: [UInt8], width: Int = 8, binary: Bool = false) -> String {
        guard width > 0 else { return "" }
        return stride(from: 0, to: bytes.count, by: width).map { start in
            row(bytes[start..<min(start + width, bytes.count)], offset: start, width: width, binary: binary)
        }.joined(separator: "\n")
    }
}
