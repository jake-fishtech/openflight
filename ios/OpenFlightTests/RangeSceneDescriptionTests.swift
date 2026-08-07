import XCTest
@testable import OpenFlight

final class RangeSceneDescriptionTests: XCTestCase {
    func testStandardSceneHasExpectedRangeMarkers() {
        let scene = RangeSceneDescription.standard(treeCount: 20)

        XCTAssertEqual(scene.markers.map(\.yards), [50, 100, 150, 200, 250, 300, 350])
        XCTAssertEqual(scene.rangeDepthMeters, 390)
        XCTAssertGreaterThan(scene.fairwayWidthMeters, 40)
    }

    func testTreePopulationIsBoundedAndPlacedOutsideFairway() {
        let scene = RangeSceneDescription.standard(treeCount: 36)

        XCTAssertEqual(scene.trees.count, 36)
        XCTAssertTrue(scene.trees.allSatisfy { abs($0.xMeters) >= 32 })
        XCTAssertTrue(scene.trees.allSatisfy { $0.downrangeMeters >= 22 })
    }

    func testQualityProfilesBoundReusableResources() {
        XCTAssertLessThan(RangeQualityProfile.balanced.treeCount, RangeQualityProfile.high.treeCount)
        XCTAssertLessThan(
            RangeQualityProfile.balanced.tracerPointCount,
            RangeQualityProfile.high.tracerPointCount
        )
        XCTAssertLessThanOrEqual(RangeQualityProfile.high.tracerPointCount, 120)
    }

    func testContinuousTracerIsThinTranslucentAndCompensatesForDistance() {
        let style = RangeTracerStyle.highVisibility

        XCTAssertLessThan(style.nearWidthMeters, 0.10)
        XCTAssertGreaterThan(style.farWidthMeters, style.nearWidthMeters)
        XCTAssertGreaterThan(style.opacity, 0.75)
        XCTAssertLessThan(style.opacity, 1)
    }
}
