import Foundation

enum BLEFrameError: LocalizedError, Equatable {
    case invalidSize
    case unsupportedVersion(UInt8)
    case invalidMetadata
    case inconsistentFragmentCount

    var errorDescription: String? {
        switch self {
        case .invalidSize:
            "Received a BLE frame with an invalid size."
        case let .unsupportedVersion(version):
            "BLE frame version \(version) is not supported."
        case .invalidMetadata:
            "Received invalid BLE fragment metadata."
        case .inconsistentFragmentCount:
            "Fragments for one BLE message disagree about its size."
        }
    }
}

struct BLEFrameReassembler {
    static let frameVersion: UInt8 = 1
    static let headerSize = 5
    static let maximumFrameSize = 20

    private var sequence: UInt16?
    private var fragmentCount: UInt8?
    private var fragments: [UInt8: Data] = [:]

    mutating func append(_ frame: Data) throws -> Data? {
        guard frame.count >= Self.headerSize, frame.count <= Self.maximumFrameSize else {
            throw BLEFrameError.invalidSize
        }

        let version = frame[frame.startIndex]
        guard version == Self.frameVersion else {
            throw BLEFrameError.unsupportedVersion(version)
        }

        let highByte = UInt16(frame[frame.startIndex + 1])
        let lowByte = UInt16(frame[frame.startIndex + 2])
        let incomingSequence = (highByte << 8) | lowByte
        let index = frame[frame.startIndex + 3]
        let incomingCount = frame[frame.startIndex + 4]
        guard incomingCount > 0, index < incomingCount else {
            throw BLEFrameError.invalidMetadata
        }

        if sequence != incomingSequence {
            reset()
            sequence = incomingSequence
            fragmentCount = incomingCount
        } else if fragmentCount != incomingCount {
            reset()
            throw BLEFrameError.inconsistentFragmentCount
        }

        fragments[index] = frame.dropFirst(Self.headerSize)
        guard fragments.count == Int(incomingCount) else {
            return nil
        }

        var message = Data()
        for expectedIndex in UInt8(0)..<incomingCount {
            guard let fragment = fragments[expectedIndex] else {
                return nil
            }
            message.append(fragment)
        }
        reset()
        return message
    }

    mutating func reset() {
        sequence = nil
        fragmentCount = nil
        fragments.removeAll(keepingCapacity: true)
    }
}
