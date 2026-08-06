import XCTest
@testable import OpenFlight

final class RangeCameraPlannerTests: XCTestCase {
    func testFixedCameraPoseLooksDownrangeFromBehindTee() {
        let pose = RangeCameraPlanner().pose

        XCTAssertEqual(pose.position, SIMD3<Float>(0, 3.4, 8))
        XCTAssertEqual(pose.target, SIMD3<Float>(0, 9, -145))
        XCTAssertGreaterThan(pose.position.z, 0)
        XCTAssertLessThan(pose.target.z, 0)
    }
}
