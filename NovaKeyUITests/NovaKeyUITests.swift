//
//  NovaKeyUITests.swift
//  NovaKeyUITests
//
//  Created by Robert Osborne on 12/17/25.
//

import XCTest

final class NovaKeyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Skip in CI environments to avoid AX runner initialization flakiness.
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            try XCTSkipIf(true, "Skipping UI tests on CI (AX initialization timeout is common on simulators in CI).")
        }

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists)
    }
}
