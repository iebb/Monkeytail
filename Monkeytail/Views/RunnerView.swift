import SwiftUI
import UniformTypeIdentifiers
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct RunReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .xml] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CollectionRunnerView: View {
    @Bindable var store: WorkspaceStore
    let collectionID: UUID
    let folderID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Configure"
    @State private var selected: Set<UUID> = []
    @State private var iterations = 1
    @State private var delay = 0
    @State private var stopOnFailure = false
    @State private var data: [[String: String]] = []
    @State private var dataName: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var exportFormat: RunnerReportFormat = .json
    @State private var document: RunReportDocument?
    @State private var failedOnly = false
    @State private var expanded: UUID?
    @State private var error: String?

    private var plan: [APIRequest] { store.runPlan(collectionID: collectionID, folderID: folderID) }
    private var run: CollectionRun? {
        guard let run = store.collectionRun, run.collectionID == collectionID, run.folderID == folderID else { return nil }
        return run
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Runner view", selection: $tab) { Text("Configure").tag("Configure"); Text("Results").tag("Results") }
                        .pickerStyle(.segmented).labelsHidden()
                    if tab == "Configure" { configuration } else { results }
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red) }
                }.padding(12)
            }.background(Palette.canvas).sheetTitle("Run \(store.runName(collectionID: collectionID, folderID: folderID))")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if run?.running == true {
                            Button("Stop", role: .destructive) { store.stopRun() }.accessibilityIdentifier("Stop run")
                        } else {
                            Button("Run", action: start).disabled(selected.isEmpty || store.runningID != nil || store.collectionRun?.running == true)
                                .accessibilityIdentifier("Start run")
                        }
                    }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .json, .plainText]) { result in
                    do {
                        let url = try result.get()
                        let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= RunnerData.maximumBytes else { throw ClientError("Data files must be smaller than 10 MB.") }
                        data = try RunnerData.parse(Data(contentsOf: url), filename: url.lastPathComponent)
                        dataName = url.lastPathComponent; iterations = data.count; error = nil
                    } catch { self.error = error.localizedDescription }
                }
                .fileExporter(isPresented: $exporting, document: document, contentType: exportFormat == .json ? .json : .xml,
                              defaultFilename: "monkeytail-run.\(exportFormat.fileExtension)") { result in
                    if case .failure(let failure) = result { error = failure.localizedDescription }
                }
                .onAppear {
                    selected = Set(plan.map(\.id))
                    if run != nil { tab = "Results" }
                }
        }.frame(idealWidth: 680, idealHeight: 640).macSheetFrame(minWidth: 560, minHeight: 480)
    }

    @ViewBuilder private var configuration: some View {
        HStack {
            Text("Requests").font(.headline)
            Spacer()
            Button(selected.count == plan.count ? "Select none" : "Select all") {
                selected = selected.count == plan.count ? [] : Set(plan.map(\.id))
            }.font(.subheadline).disabled(plan.isEmpty)
        }
        if plan.isEmpty {
            Text("No HTTP or GraphQL requests here. WebSocket and SSE requests are not run.").font(.subheadline).foregroundStyle(.secondary)
        }
        VStack(spacing: 0) {
            ForEach(plan) { request in
                Button {
                    if selected.contains(request.id) { selected.remove(request.id) } else { selected.insert(request.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected.contains(request.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(request.id) ? Palette.mint : Color.secondary)
                        MethodBadge(method: request.method)
                        Text(request.name).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 40).padding(.horizontal, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(request.id) ? .isSelected : [])
                if request.id != plan.last?.id { Divider() }
            }
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border))
        Text("Options").font(.headline).padding(.top, 4)
        VStack(alignment: .leading, spacing: 10) {
            Stepper("Iterations: \(iterations)", value: $iterations, in: 1...RunnerData.maximumRows)
            Stepper("Delay between requests: \(delay) ms", value: $delay, in: 0...10_000, step: 100)
            Toggle("Stop at the first failure", isOn: $stopOnFailure)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Data file").font(.subheadline.weight(.medium))
                    if let dataName {
                        Text("\(dataName) · \(data.count) \(data.count == 1 ? "row" : "rows") · \(columns)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text("CSV with a header row, or a JSON array of objects. Each row supplies {{column}} values for one iteration.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if dataName != nil { Button("Remove", role: .destructive) { data = []; dataName = nil; iterations = 1 }.font(.subheadline) }
                Button { importing = true } label: { Label("Choose", systemImage: "doc") }.buttonStyle(.bordered)
            }
        }.font(.subheadline).padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        Text("Requests run in sidebar order with \(store.environment.map { "the “\($0.name)” environment" } ?? "no environment"). Variables set by scripts carry to later requests and are saved to the active environment. Scripts can use pm.iterationData, pm.info, and pm.execution.setNextRequest(name) or setNextRequest(null) to end an iteration. When iterations exceed data rows, the last row repeats.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var columns: String {
        let names = Set(data.flatMap(\.keys)).sorted()
        return names.prefix(6).joined(separator: ", ") + (names.count > 6 ? "…" : "")
    }

    @ViewBuilder private var results: some View {
        if let run {
            let report = run.report
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    summary("Requests", "\(report.sentCount)")
                    summary("Failed", "\(report.failedCount)", tint: report.failedCount > 0 ? Palette.danger : nil)
                    summary("Tests", "\(report.testCount - report.failedTestCount)/\(report.testCount)")
                    summary("Time", String(format: "%.2f s", report.totalDuration))
                    Spacer(minLength: 0)
                }
                if run.running {
                    ProgressView(value: Double(min(report.results.count, run.expectedCount)), total: Double(max(run.expectedCount, 1)))
                    if let name = run.currentName { Text("Running \(name)…").font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(run.notes, id: \.self) { Label($0, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Toggle("Failures only", isOn: $failedOnly).toggleStyle(.button).font(.subheadline)
                Spacer()
                Menu {
                    ForEach(RunnerReportFormat.allCases) { format in
                        Button(format.rawValue) {
                            do { document = RunReportDocument(data: try RunnerReportCodec.encode(report, format: format)); exportFormat = format; exporting = true }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                } label: { Label("Export report", systemImage: "square.and.arrow.up") }.disabled(run.running || report.results.isEmpty)
            }
            Text("Reports include sent URLs, statuses, timings, and test names, not response bodies.").font(.caption).foregroundStyle(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(report.results.filter { !failedOnly || !$0.passed }) { result in
                    row(result)
                    Divider()
                }
            }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        } else {
            EmptyPanel(title: "No results yet", message: "Configure the run, then choose Run.", symbol: "play.circle").frame(minHeight: 240)
        }
    }

    private func summary(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .monospaced, weight: .semibold)).foregroundStyle(tint ?? .primary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func row(_ result: RunnerResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded = expanded == result.id ? nil : result.id } label: {
                HStack(spacing: 8) {
                    Image(systemName: result.skipped ? "forward.circle" : result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(result.skipped ? Color.secondary : result.passed ? Palette.mint : Palette.danger)
                    Text("#\(result.iteration)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    MethodBadge(method: result.method)
                    Text(result.name).font(.subheadline).lineLimit(1)
                    Spacer(minLength: 0)
                    if !result.tests.isEmpty { Text("\(result.tests.filter(\.passed).count)/\(result.tests.count)").font(.caption).foregroundStyle(.secondary) }
                    if let status = result.status { StatusBadge(status: status, showsLabel: false) }
                    else { Text(result.skipped ? "Skipped" : "Error").font(.system(.caption, design: .monospaced)).foregroundStyle(result.skipped ? Color.secondary : .red) }
                    Text("\(Int(result.duration * 1000)) ms").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }.frame(minHeight: 40).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded == result.id {
                Text(result.url).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                if let error = result.error { Text(error).font(.caption).foregroundStyle(Palette.danger) }
                ForEach(Array(result.tests.enumerated()), id: \.offset) { _, test in
                    Label(test.name, systemImage: test.passed ? "checkmark" : "xmark").font(.caption).foregroundStyle(test.passed ? Palette.mint : Palette.danger)
                }
                if let body = result.bodyPreview, !body.isEmpty {
                    Text(body).font(.system(.caption2, design: .monospaced)).lineLimit(20).textSelection(.enabled)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }.padding(.horizontal, 10).padding(.vertical, 2)
    }

    private func start() {
        error = nil
        store.startRun(collectionID: collectionID, folderID: folderID,
                       configuration: RunConfiguration(requestIDs: selected, iterations: iterations, delayMilliseconds: delay, data: data, stopOnFailure: stopOnFailure))
        if let issue = store.issue { error = issue; store.issue = nil; return }
        if run != nil { tab = "Results"; expanded = nil }
    }
}
