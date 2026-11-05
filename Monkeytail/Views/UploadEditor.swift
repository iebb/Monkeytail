import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct UploadFileEditor: View {
    @Binding var file: RequestFile?
    @State private var choosing = false
    @State private var photo: PhotosPickerItem?
    @State private var loading = false
    @State private var share: UploadShare?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { choosing = true } label: { Label(file?.data == nil ? "Choose file" : "Replace file", systemImage: "doc") }.frame(minHeight: 44)
                PhotosPicker(selection: $photo, matching: .any(of: [.images, .videos])) { Image(systemName: "photo").frame(width: 44, height: 44) }.accessibilityLabel("Choose photo or video")
                Spacer()
                if loading { ProgressView() }
                if file != nil { Button { file = nil } label: { Image(systemName: "xmark.circle").frame(width: 44, height: 44) }.accessibilityLabel("Remove file") }
            }
            if let current = file {
                Text(current.filename.isEmpty ? String(localized: "No file selected") : current.filename).font(.system(.caption, design: .monospaced)).lineLimit(2)
                if let data = current.data {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Export file") {
                            Task {
                                do {
                                    let url = try await Task.detached {
                                        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("upload-export-" + UUID().uuidString, isDirectory: true)
                                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                        let name = URL(fileURLWithPath: current.filename).lastPathComponent
                                        let url = folder.appendingPathComponent(name.isEmpty ? "attachment.bin" : name)
                                        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen]); return url
                                    }.value
                                    share = UploadShare(url: url)
                                } catch { self.error = error.localizedDescription }
                            }
                        }.font(.caption).frame(minHeight: 44)
                    }
                }
                else { Text("Choose this file on your device.").font(.caption).foregroundStyle(Palette.warning) }
                TextField("MIME type", text: Binding(get: { file?.mimeType ?? "" }, set: { file?.mimeType = $0 })).font(.system(.caption, design: .monospaced)).dismissibleInput()
            }
            if let error { Text(error).font(.caption).foregroundStyle(Palette.error) }
        }.noCapitalization().autocorrectionDisabled()
            .sheet(item: $share) { item in ShareSheet(items: [item.url]) }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.data]) { result in
                switch result {
                case .failure(let failure): error = failure.localizedDescription
                case .success(let url):
                    loading = true
                    Task {
                        defer { loading = false }
                        do {
                            let selected = try await Task.detached(priority: .userInitiated) {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }
                                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                                guard (values.fileSize ?? 0) <= MultipartEncoder.maximumBytes else { throw ClientError(String(localized: "Upload exceeds the 20 MB limit.")) }
                                let data = try Data(contentsOf: url)
                                guard data.count <= MultipartEncoder.maximumBytes else { throw ClientError(String(localized: "Upload exceeds the 20 MB limit.")) }
                                return RequestFile(filename: url.lastPathComponent, mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream", data: data)
                            }.value
                            file = selected; error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                loading = true
                Task {
                    defer { loading = false; photo = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw ClientError(String(localized: "This photo could not be loaded.")) }
                        guard data.count <= MultipartEncoder.maximumBytes else { throw ClientError(String(localized: "Upload exceeds the 20 MB limit.")) }
                        let type = item.supportedContentTypes.first ?? .data
                        file = RequestFile(filename: "attachment." + (type.preferredFilenameExtension ?? "bin"), mimeType: type.preferredMIMEType ?? "application/octet-stream", data: data)
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }
    }
}

struct MultipartEditor: View {
    @Binding var parts: [MultipartPart]
    var body: some View {
        VStack(spacing: 10) {
            ForEach($parts) { $part in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button { part.enabled.toggle() } label: { Image(systemName: part.enabled ? "checkmark.square.fill" : "square").frame(width: 44, height: 44) }.accessibilityLabel("Enable multipart field")
                        TextField("Field name", text: $part.name).dismissibleInput().font(.system(.footnote, design: .monospaced))
                        Picker("Field type", selection: Binding(get: { part.file != nil }, set: { part.file = $0 ? RequestFile(filename: "") : nil })) { Text("Text").tag(false); Text("File").tag(true) }.labelsHidden().pickerStyle(.menu)
                        Button { parts.removeAll { $0.id == part.id } } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel("Remove multipart field")
                    }
                    if part.file != nil { UploadFileEditor(file: $part.file) }
                    else { TextField("Value", text: $part.value, axis: .vertical).dismissibleInput().font(.system(.footnote, design: .monospaced)).padding(.bottom, 10) }
                }.padding(.horizontal, 10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button { parts.append(MultipartPart()) } label: { Label("Add field", systemImage: "plus") }.frame(minHeight: 44)
                Spacer()
                Button { parts.append(MultipartPart(file: RequestFile(filename: ""))) } label: { Label("Add file", systemImage: "paperclip") }.frame(minHeight: 44)
            }
        }.noCapitalization().autocorrectionDisabled()
    }
}

private struct UploadShare: Identifiable { var id: URL { url }; let url: URL }
