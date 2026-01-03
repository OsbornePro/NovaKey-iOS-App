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

        #if targetEnvironment(simulator) && arch(x86_64)
        try XCTSkipIf(true, "Skipping UI tests on x86_64 simulator due to AX initialization timeouts.")
        #endif

        // Add this to reduce first-launch prompts affecting tests
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists)
    }
}
