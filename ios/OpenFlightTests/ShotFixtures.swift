import Foundation
import XCTest

private final class FixtureAnchor {}

/// The shot payload fixture shared with the Python tests, so both sides of the
/// contract decode the same bytes.
func sharedShotFixture() throws -> Data {
    let fixtureURL = try XCTUnwrap(
        Bundle(for: FixtureAnchor.self).url(forResource: "shot_v1", withExtension: "json")
    )
    return try Data(contentsOf: fixtureURL)
}
