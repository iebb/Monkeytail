import Foundation

// Compile alongside Sources/MonkeytailCore/*.swift to regenerate the examples.
@main
struct ExportSamples {
    static func main() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/examples")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (format, name) in [(ExportFormat.native, "playground.monkeytail.json"), (.postman, "playground.postman_collection.json"), (.insomnia, "playground.insomnia.json")] {
            try CollectionCodec.encode(.starter, format: format).write(to: directory.appendingPathComponent(name))
        }
    }
}
