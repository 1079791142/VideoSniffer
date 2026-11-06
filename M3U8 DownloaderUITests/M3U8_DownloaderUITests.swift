//
//  M3U8_DownloaderUITests.swift
//  M3U8 DownloaderUITests
//
//  Created by 林思行 on 2026/5/14.
//

import XCTest

final class M3U8_DownloaderUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

#if !os(macOS)
    @MainActor
    func testSettingsSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Settings"].click()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].exists)
    }
#endif

}
