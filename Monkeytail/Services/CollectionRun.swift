import Foundation
import Observation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct RunConfiguration {
    var requestIDs: Set<UUID>
    var iterations = 1
    var delayMilliseconds = 0
    var data: [[String: String]] = []
    var stopOnFailure = false
}

@MainActor @Observable
final class CollectionRun {
    let collectionID: UUID
    let folderID: UUID?
    var report: RunnerReport
    var expectedCount: Int
    var running = true
    var currentName: String?
    var notes: [String] = []
    fileprivate var task: Task<Void, Never>?
    init(collectionID: UUID, folderID: UUID?, report: RunnerReport, expectedCount: Int) {
        self.collectionID = collectionID; self.folderID = folderID; self.report = report; self.expectedCount = expectedCount
    }
}

extension WorkspaceStore {
    static let maximumRunRequests = 10_000
    static let runBodyPreviewBytes = 4096

    func runPlan(collectionID: UUID, folderID: UUID?) -> [APIRequest] {
        guard let collection = workspace.collections.first(where: { $0.id == collectionID }) else { return [] }
        return RunnerPlan.requests(in: collection, folderID: folderID)
    }

    func runName(collectionID: UUID, folderID: UUID?) -> String {
        let collection = workspace.collections.first { $0.id == collectionID }
        return collection?.folders?.first { $0.id == folderID }?.name ?? collection?.name ?? "Collection"
    }

    /// Runs selected requests in sidebar order. Script variable edits carry forward within the run,
    /// and are also saved to the active environment, as they are for single sends.
    func startRun(collectionID: UUID, folderID: UUID?, configuration: RunConfiguration) {
        guard runningID == nil, collectionRun?.running != true else { issue = "Wait for the current request to finish."; return }
        let plan = runPlan(collectionID: collectionID, folderID: folderID).filter { configuration.requestIDs.contains($0.id) }
        guard !plan.isEmpty else { issue = "Select at least one HTTP or GraphQL request to run."; return }
        let iterations = max(1, min(RunnerData.maximumRows, configuration.iterations))
        let environmentID = workspace.selectedEnvironmentID
        let run = CollectionRun(collectionID: collectionID, folderID: folderID,
                                report: RunnerReport(name: runName(collectionID: collectionID, folderID: folderID), environment: environment?.name, iterations: iterations),
                                expectedCount: plan.count * iterations)
        collectionRun = run
        run.task = Task {
            defer { run.running = false; run.currentName = nil; run.report.finishedAt = Date(); run.task = nil }
            var overlay: [String: String] = [:], executed = 0
            iterationLoop: for iteration in 0..<iterations {
                let row = configuration.data.isEmpty ? [:] : configuration.data[min(iteration, configuration.data.count - 1)]
                var index: Int? = 0
                while let current = index {
                    guard executed < Self.maximumRunRequests else { run.notes.append("Stopped after \(Self.maximumRunRequests) requests."); break iterationLoop }
                    if executed > 0, configuration.delayMilliseconds > 0 { try? await Task.sleep(for: .milliseconds(configuration.delayMilliseconds)) }
                    if Task.isCancelled { run.notes.append("Run stopped."); break iterationLoop }
                    executed += 1
                    // Use the latest saved definition so edits during a run apply to later requests.
                    let saved = request(plan[current].id) ?? plan[current]
                    run.currentName = saved.name
                    var result = RunnerResult(iteration: iteration + 1, request: saved), directive: RunnerDirective?
                    do {
                        let execution = try await execute(saved, environmentID: environmentID, proxy: workspace.proxy,
                                                          scope: overlay.merging(row) { _, data in data },
                                                          context: ScriptContext(iterationData: row, iteration: iteration, iterationCount: iterations))
                        for (key, value) in execution.changes { overlay[key] = value }
                        directive = execution.directive
                        if !execution.url.isEmpty { result.url = execution.url }
                        if let response = execution.response {
                            result.status = response.status; result.duration = response.duration
                            result.tests = response.logs.filter { $0.level == "pass" || $0.level == "fail" }.map { RunnerTest(name: $0.message, passed: $0.level == "pass") }
                            if let error = execution.scriptError { result.tests.append(RunnerTest(name: "After-response script: " + error, passed: false)) }
                            result.bodyPreview = String(decoding: response.body.prefix(Self.runBodyPreviewBytes), as: UTF8.self)
                        } else { result.skipped = true }
                    } catch {
                        if Task.isCancelled { run.notes.append("Run stopped."); break iterationLoop }
                        result.error = error.localizedDescription
                    }
                    run.report.results.append(result)
                    if configuration.stopOnFailure && !result.passed { run.notes.append("Stopped at the first failure."); break iterationLoop }
                    index = RunnerPlan.nextIndex(after: current, directive: directive, plan: plan)
                    if case .jump(let target) = directive, index == nil { run.notes.append("Iteration \(iteration + 1): next request “\(target)” is not in this run.") }
                }
            }
        }
    }

    func stopRun() { collectionRun?.task?.cancel() }
}
