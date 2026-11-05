import XCTest
@testable import MonkeytailCore

final class WorkspacesTests: XCTestCase {
    private func sample() -> (Workspace, WorkspaceInfo) {
        var workspace = Workspace.starter
        let team = WorkspaceInfo(name: "Team", globals: [Field("region", "us"), Field("api_token", "team-private")])
        workspace.workspaces = [team]
        var collection = RequestCollection(name: "Payments", requests: [APIRequest(name: "Charge")]); collection.workspaceID = team.id
        var environment = APIEnvironment(name: "Prod", variables: [Field("host", "api.example.com")]); environment.workspaceID = team.id
        workspace.collections.append(collection); workspace.environments.append(environment)
        workspace.selectEnvironment(environment.id, in: team.id)
        return (workspace, team)
    }

    func testCollectionsEnvironmentsAndGlobalsAreScopedToTheirWorkspace() {
        let (workspace, team) = sample(), main = Workspace.defaultWorkspaceID
        XCTAssertEqual(workspace.workspaceList.map(\.id), [main, team.id])
        XCTAssertEqual(workspace.collections(in: main).map(\.name), ["Getting started"])
        XCTAssertEqual(workspace.collections(in: team.id).map(\.name), ["Payments"])
        XCTAssertEqual(workspace.environments(in: team.id).map(\.name), ["Prod"])
        XCTAssertEqual(workspace.globalValues(in: team.id)["region"], "us"); XCTAssertTrue(workspace.globals(in: main).isEmpty)
        XCTAssertEqual(workspace.selectedEnvironmentID(in: team.id), workspace.environments.last?.id)
        XCTAssertEqual(workspace.selectedEnvironmentID(in: main), workspace.environments.first?.id)
        XCTAssertEqual(workspace.workspaceID(ofRequest: workspace.collections.last?.requests.first?.id), team.id)
    }

    func testItemsOfAMissingWorkspaceFallBackToTheDefault() {
        var (workspace, team) = sample()
        workspace.workspaces = []
        XCTAssertEqual(workspace.collections(in: Workspace.defaultWorkspaceID).count, 2)
        workspace.workspaces = [team]
        workspace.removeWorkspace(team.id)
        XCTAssertEqual(workspace.collections.map(\.name), ["Getting started"]); XCTAssertEqual(workspace.environments.map(\.name), ["Playground"])
        workspace.removeWorkspace(Workspace.defaultWorkspaceID)
        XCTAssertEqual(workspace.collections.count, 1)
    }

    func testSyncCarriesWorkspacesAndStripsTheirSecretGlobals() throws {
        let (workspace, team) = sample()
        var state = WorkspaceSyncState(); try state.capture(workspace)
        for record in state.records { XCTAssertFalse(String(decoding: record.payload ?? Data(), as: UTF8.self).contains("team-private")) }
        let fresh = try state.workspace(local: Workspace())
        XCTAssertEqual(fresh.workspaces?.map(\.name), ["Team"])
        XCTAssertEqual(fresh.collections(in: team.id).map(\.name), ["Payments"]); XCTAssertEqual(fresh.environments(in: team.id).map(\.name), ["Prod"])
        XCTAssertEqual(fresh.globalValues(in: team.id)["region"], "us"); XCTAssertEqual(fresh.globals(in: team.id).last?.value, "")
        XCTAssertEqual(fresh.selectedEnvironmentID, fresh.environments(in: Workspace.defaultWorkspaceID).first?.id)
        XCTAssertEqual(try state.workspace(local: workspace).globals(in: team.id).last?.value, "team-private")

        var removed = workspace; removed.removeWorkspace(team.id)
        try state.capture(removed)
        let merged = try state.workspace(local: workspace)
        XCTAssertNil(merged.workspaces); XCTAssertEqual(merged.collections.map(\.name), ["Getting started"])
    }
}
