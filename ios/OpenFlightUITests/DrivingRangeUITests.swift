import XCTest

final class DrivingRangeUITests: XCTestCase {
    func testEntersRangeShowsMetricsAndExits() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-shot"]
        app.launch()

        let rangeButton = app.buttons["dashboard.range"]
        XCTAssertTrue(rangeButton.waitForExistence(timeout: 3))
        rangeButton.tap()

        XCTAssertTrue(app.buttons["range.exit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["range.ballSpeed"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["range.carry"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["range.clubSelector"].exists)

        app.buttons["range.exit"].tap()
        XCTAssertTrue(rangeButton.waitForExistence(timeout: 3))
    }
}
