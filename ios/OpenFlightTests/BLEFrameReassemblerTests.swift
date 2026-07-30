import XCTest
@testable import OpenFlight

final class BLEFrameReassemblerTests: XCTestCase {
    func testReassemblesOrderedAndOutOfOrderFrames() throws {
        let payload = Data("a payload that requires several BLE fragments".utf8)
        let frames = makeBLEFrames(payload, sequence: 42)

        var ordered = BLEFrameReassembler()
        var orderedResult: Data?
        for frame in frames {
            orderedResult = try ordered.append(frame) ?? orderedResult
        }

        var reversed = BLEFrameReassembler()
        var reversedResult: Data?
        for frame in frames.reversed() {
            reversedResult = try reversed.append(frame) ?? reversedResult
        }

        XCTAssertEqual(orderedResult, payload)
        XCTAssertEqual(reversedResult, payload)
    }

    func testDuplicateFragmentIsIgnored() throws {
        let payload = Data("this message needs more than one frame".utf8)
        let frames = makeBLEFrames(payload, sequence: 7)
        var reassembler = BLEFrameReassembler()

        XCTAssertNil(try reassembler.append(frames[0]))
        XCTAssertNil(try reassembler.append(frames[0]))

        var result: Data?
        for frame in frames.dropFirst() {
            result = try reassembler.append(frame) ?? result
        }
        XCTAssertEqual(result, payload)
    }

    func testNewSequenceReplacesIncompleteMessage() throws {
        let oldFrames = makeBLEFrames(Data("old incomplete message".utf8), sequence: 1)
        let newPayload = Data("new complete message".utf8)
        let newFrames = makeBLEFrames(newPayload, sequence: 2)
        var reassembler = BLEFrameReassembler()

        XCTAssertNil(try reassembler.append(oldFrames[0]))
        var result: Data?
        for frame in newFrames {
            result = try reassembler.append(frame) ?? result
        }

        XCTAssertEqual(result, newPayload)
    }

    func testRejectsMalformedFrames() {
        var reassembler = BLEFrameReassembler()

        XCTAssertThrowsError(try reassembler.append(Data([1, 0, 1, 0])))
        XCTAssertThrowsError(try reassembler.append(Data([2, 0, 1, 0, 1, 65])))
        XCTAssertThrowsError(try reassembler.append(Data([1, 0, 1, 2, 1, 65])))
    }
}
