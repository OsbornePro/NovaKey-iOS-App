//
//  NovaKeyUITestsLaunchTests.swift
//  NovaKeyUITests
//
//  Created by Robert Osborne on 12/17/25.
//

import XCTest

final class NovaKeyUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false

        #if targetEnvironment(simulator) && arch(x86_64)
        try XCTSkipIf(true, "Skipping UI tests on x86_64 simulator due to AX initialization timeouts.")
        #endif
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
