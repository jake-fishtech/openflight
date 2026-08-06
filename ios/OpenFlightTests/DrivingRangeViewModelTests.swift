import XCTest
@testable import OpenFlight

@MainActor
final class DrivingRangeViewModelTests: XCTestCase {
    func testExistingShotIsDisplayedWithoutAutomaticReplay() {
        let shot = makeDrivingRangeShot()
        let viewModel = makeViewModel(currentShot: shot)

        XCTAssertEqual(viewModel.displayedShot, shot)
        XCTAssertEqual(viewModel.phase, .waiting)
        XCTAssertNil(viewModel.activeTrajectory)
    }

    func testNewShotPreparesAndStartsFlight() async {
        let viewModel = makeViewModel()
        let shot = makeDrivingRangeShot()

        viewModel.observe(shot)
        await waitUntil { viewModel.phase == .flying }

        XCTAssertEqual(viewModel.displayedShot, shot)
        XCTAssertEqual(viewModel.activeTrajectory?.eventID, shot.eventID)
    }

    func testOnlyNewestPendingShotPlaysAfterCurrentFlight() async {
        let first = makeDrivingRangeShot()
        let second = makeDrivingRangeShot(ballSpeedMPH: 140)
        let newest = makeDrivingRangeShot(ballSpeedMPH: 160)
        let viewModel = makeViewModel()

        viewModel.observe(first)
        await waitUntil { viewModel.phase == .flying }
        viewModel.observe(second)
        viewModel.observe(newest)
        viewModel.animationCompleted()
        await waitUntil {
            viewModel.phase == .flying && viewModel.displayedShot?.eventID == newest.eventID
        }

        XCTAssertEqual(viewModel.displayedShot, newest)
        XCTAssertNotEqual(viewModel.displayedShot, second)
    }

    func testReplayStartsDisplayedShotAgain() async {
        let shot = makeDrivingRangeShot()
        let viewModel = makeViewModel(currentShot: shot)

        viewModel.replayDisplayedShot()
        await waitUntil { viewModel.phase == .flying }

        XCTAssertEqual(viewModel.activeTrajectory?.eventID, shot.eventID)
    }

    func testInvalidShotSurfacesUnavailableState() {
        let viewModel = makeViewModel()

        viewModel.observe(makeDrivingRangeShot(ballSpeedMPH: 0))

        XCTAssertEqual(viewModel.phase, .unavailable("Ball speed is unavailable for this shot."))
        XCTAssertNil(viewModel.activeTrajectory)
    }

    func testSuspendCancelsAndReturnsToWaiting() async {
        let viewModel = makeViewModel()
        viewModel.observe(makeDrivingRangeShot())
        await waitUntil { viewModel.phase == .flying }

        viewModel.suspend()

        XCTAssertEqual(viewModel.phase, .waiting)
        XCTAssertNil(viewModel.activeTrajectory)
    }

    private func makeViewModel(currentShot: ShotEvent? = nil) -> DrivingRangeViewModel {
        DrivingRangeViewModel(
            currentShot: currentShot,
            simulation: { makeTestTrajectory(for: $0) },
            sleep: { _ in }
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not reached", file: file, line: line)
    }
}

