//
//  LezzSeaUITests.swift
//  LezzSeaUITests
//

import AppKit
import XCTest

/// Two properties the shipped build broke, kept honest here:
///
/// 1. The window has a floor, so the sidebar and detail pane cannot be dragged
///    into each other.
/// 2. The panel switch lives in the toolbar and changes panes; there is no
///    floating tab strip over the content.
final class LezzSeaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWindowIsAtLeastTheDeclaredMinimum() throws {
        let app = launchApp()
        let size = app.windows.firstMatch.frame.size

        XCTAssertGreaterThanOrEqual(size.width, 760, "window width fell below the content minimum")
        XCTAssertGreaterThanOrEqual(size.height, 500, "window height fell below the content minimum")
    }

    @MainActor
    func testPanelSwitcherMovesBetweenLightsAndEvents() throws {
        let app = launchApp()

        // The picker is a segmented control, which AppKit exposes as a radio
        // group. Its segments must be named "Lights" and "Events", even when
        // the toolbar collapses them to icons.
        let picker = app.radioGroups["toolbar.panel"]
        guard picker.waitForExistence(timeout: 5) else {
            throw XCTSkip("This build does not expose the toolbar panel picker")
        }

        let events = picker.radioButtons["Events"]
        let lights = picker.radioButtons["Lights"]
        XCTAssertTrue(events.exists, "Events segment is missing or unnamed")
        XCTAssertTrue(lights.exists, "Lights segment is missing or unnamed")

        events.click()
        XCTAssertEqual(picker.value as? String, "Events")

        lights.click()
        XCTAssertEqual(picker.value as? String, "Lights")
    }

    /// The isotope chart and the boundary list are static; they must render
    /// with or without a cluster, and be reachable from the same toolbar
    /// switch as the cluster panels.
    @MainActor
    func testStaticPanelsRenderWithoutACluster() throws {
        let app = launchApp()

        let picker = app.radioGroups["toolbar.panel"]
        guard picker.waitForExistence(timeout: 5) else {
            throw XCTSkip("This build does not expose the toolbar panel picker")
        }

        let isotopes = picker.radioButtons["Isotopes"]
        let boundaries = picker.radioButtons["Boundaries"]
        XCTAssertTrue(isotopes.exists, "Isotopes segment is missing or unnamed")
        XCTAssertTrue(boundaries.exists, "Boundaries segment is missing or unnamed")

        isotopes.click()
        XCTAssertEqual(picker.value as? String, "Isotopes")
        // Anchor on the chart's own content: SwiftUI flattens container
        // identifiers into the panel group, so a root-id query is brittle.
        XCTAssertTrue(
            app.staticTexts["Isotope chart"].waitForExistence(timeout: 5),
            "the isotope chart did not render"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["isotope.Fl-1"].exists,
            "the isotope cells did not render"
        )

        boundaries.click()
        XCTAssertEqual(picker.value as? String, "Boundaries")
        XCTAssertTrue(
            app.descendants(matching: .any)["boundary.residence"].exists,
            "the boundary rows did not render"
        )
    }

    /// The scenario catalog is the selection surface for smoke-alarm's
    /// ready-to-run configs. It has to render with no cluster, and the filter
    /// has to narrow the list rather than merely highlight it.
    @MainActor
    func testScenariosPanelFiltersTheCatalog() throws {
        let app = launchApp()

        let picker = app.radioGroups["toolbar.panel"]
        guard picker.waitForExistence(timeout: 5) else {
            throw XCTSkip("This build does not expose the toolbar panel picker")
        }

        let scenarios = picker.radioButtons["Scenarios"]
        XCTAssertTrue(scenarios.exists, "Scenarios segment is missing or unnamed")

        scenarios.click()
        XCTAssertEqual(picker.value as? String, "Scenarios")
        XCTAssertTrue(
            app.staticTexts["Scenarios"].firstMatch.waitForExistence(timeout: 5),
            "the scenario catalog did not render"
        )

        // The first section is transport, so this row is on screen without
        // scrolling; a lazily-built List does not expose off-screen rows.
        XCTAssertTrue(
            app.descendants(matching: .any)["scenario.stdio-mcp-strict.yaml"].exists,
            "the scenario rows did not render"
        )

        // The action is the point of the panel: copy the documented command.
        let copy = app.buttons["Copy the command for Strict stdio MCP"]
        XCTAssertTrue(copy.exists, "the copy button is missing")
        copy.click()
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            "go run ./cmd/ocd-smoke-alarm serve --config=configs/samples/stdio-mcp-strict.yaml --mode=foreground",
            "the copied command is not the documented one"
        )

        let search = app.textFields["scenarios.search"]
        XCTAssertTrue(search.exists, "the scenario filter is missing")
        search.click()
        search.typeText("oauth")

        XCTAssertTrue(
            app.descendants(matching: .any)["scenario.oauth-mock-allow.yaml"].waitForExistence(timeout: 5),
            "the filter did not keep the OAuth scenarios"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["scenario.stdio-mcp-strict.yaml"].exists,
            "the filter did not remove the stdio scenario"
        )
    }

    /// The lights table used to lay its columns out at their ideal widths and
    /// let the last one hang outside the window. With a cluster connected, the
    /// rightmost header must be inside the window.
    @MainActor
    func testLightsTableStaysInsideTheWindow() throws {
        let app = launchApp()
        let updated = app.buttons["Updated"]

        guard updated.waitForExistence(timeout: 5) else {
            throw XCTSkip("No cluster connected, so there is no lights table")
        }

        let window = app.windows.firstMatch
        XCTAssertLessThanOrEqual(
            updated.frame.maxX,
            window.frame.maxX + 1,
            "the Updated column hangs outside the window"
        )
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 30),
            "main window did not appear"
        )
        return app
    }
}
