//
//  LabClusterUITests.swift
//  LezzSeaUITests
//
//  Verifies the launcher against a cluster it did not start.
//
//  Run `scripts/lab-cluster.sh` first, then run this test with the Lab build
//  settings so the app under test is the unsandboxed build that reads the same
//  Application Support directory the script registers into:
//
//    xcodebuild -project LezzSea.xcodeproj -scheme LezzSea \
//      -destination 'platform=macOS' \
//      CODE_SIGN_ENTITLEMENTS=LezzSea/LezzSea-Lab.entitlements \
//      SWIFT_ACTIVE_COMPILATION_CONDITIONS=LAB_LAUNCHER \
//      ENABLE_APP_SANDBOX=NO ENABLE_USER_SELECTED_FILES= \
//      test -only-testing:LezzSeaUITests/LabClusterUITests
//
//  Without a registered cluster (and without the Lab build) the test skips: it
//  asserts a property of the environment, not of a fixture it can invent.
//

import XCTest

final class LabClusterUITests: XCTestCase {

    private let slug = "federation-mesh"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAScriptLaunchedFederationClusterIsShown() throws {
        let cluster = try registeredCluster()
        let expected = (cluster["members"] as? [[String: Any]] ?? []).count
        let rootPort = cluster["rootPort"] as? Int ?? 5100

        try XCTSkipIf(expected == 0, "No registered federation cluster on :\(rootPort)")

        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 30),
            "main window did not appear"
        )

        let picker = app.radioGroups["toolbar.panel"]
        guard picker.waitForExistence(timeout: 5) else {
            throw XCTSkip("This build does not expose the toolbar panel picker")
        }
        picker.radioButtons["Scenarios"].click()

        // The Lab build is the only one that reads the launcher's Application
        // Support directory; the sandbox build has a container of its own and
        // must not be failed for not seeing this cluster.
        try XCTSkipIf(
            !app.buttons["Launch Strict stdio MCP via lezz"].waitForExistence(timeout: 5),
            "The sandboxed build cannot see launcher clusters; run this with the Lab build settings."
        )

        let search = app.textFields["scenarios.search"]
        XCTAssertTrue(search.exists, "the scenario filter is missing")
        search.click()
        search.typeText("federation-mesh")

        let row = app.descendants(matching: .any)["scenario.federation-mesh.yaml"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the federation mesh row did not render")

        // SwiftUI does not keep a nested identifier on a row that already has
        // one, so the badge is found by the sentence it speaks.
        let badge = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "\(expected) of \(expected) members"))
            .firstMatch
        XCTAssertTrue(
            badge.waitForExistence(timeout: 15),
            "the cluster badge did not appear for a cluster the app did not launch"
        )
        XCTAssertTrue(
            badge.label.contains("\(rootPort)"),
            "the badge did not name the root port: \(badge.label)"
        )

        // The pairing block is the other half of the property: every member's
        // bound port has to come back from mDNS, not from the sample's
        // preferred port. Poll the copy action while discovery settles.
        var endpointCount = 0
        for _ in 0..<10 {
            let more = app.descendants(matching: .any)["More actions for Federation mesh"]
            guard more.exists else { break }
            more.click()
            let item = app.menuItems["Copy adhd smoke_alarm block"]
            guard item.waitForExistence(timeout: 3) else { break }
            item.click()

            let block = NSPasteboard.general.string(forType: .string) ?? ""
            endpointCount = block.components(separatedBy: "endpoint:").count - 1
            if endpointCount == expected { break }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertEqual(
            endpointCount,
            expected,
            "the adhd block did not cover every member: discovery did not resolve the bound ports"
        )

        // The paired adhd's watcher report is read from the same cluster.json
        // and adhd.log the script wrote. With no light-update lines yet it is
        // honestly all NO COVERAGE, but the row has to be there.
        let report = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Gherkin report"))
            .firstMatch
        XCTAssertTrue(
            report.waitForExistence(timeout: 15),
            "the Gherkin report row did not appear for a paired cluster"
        )
        XCTAssertTrue(
            report.label.contains("no coverage"),
            "the report row did not carry the watcher verdict: \(report.label)"
        )
    }

    /// The launcher path itself: derive, run, find the port the alarm bound,
    /// then stop it. Only the Lab build can do this, so the test skips when the
    /// play button is compiled out.
    @MainActor
    func testTheLauncherStartsAndStopsASingleProcessScenario() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 30),
            "main window did not appear"
        )

        let picker = app.radioGroups["toolbar.panel"]
        guard picker.waitForExistence(timeout: 5) else {
            throw XCTSkip("This build does not expose the toolbar panel picker")
        }
        picker.radioButtons["Scenarios"].click()

        let launch = app.buttons["Launch Strict stdio MCP via lezz"]
        try XCTSkipIf(
            !launch.waitForExistence(timeout: 5),
            "Launching is only compiled into the Lab build"
        )

        let search = app.textFields["scenarios.search"]
        search.click()
        search.typeText("stdio-mcp-strict")
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        launch.click()

        let running = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Running on port"))
            .firstMatch
        XCTAssertTrue(
            running.waitForExistence(timeout: 30),
            "the launched alarm never reported a bound port"
        )

        let stop = app.buttons["Stop Strict stdio MCP"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "the stop button did not replace launch")
        stop.click()
        XCTAssertTrue(
            running.waitForNonExistence(timeout: 30),
            "the cluster was still shown after it was stopped"
        )
    }

    /// The contract the script writes. Reading it from the test process also
    /// proves the file is where the Lab build looks for it.
    private func registeredCluster() throws -> [String: Any] {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/LezzSea/Clusters/\(slug)/cluster.json")

        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}
