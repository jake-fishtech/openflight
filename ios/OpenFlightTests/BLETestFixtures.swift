import Foundation

func makeBLEFrames(_ payload: Data, sequence: UInt16) -> [Data] {
    let chunkSize = 15
    let count = UInt8((payload.count + chunkSize - 1) / chunkSize)
    return stride(from: 0, to: payload.count, by: chunkSize).enumerated().map {
        index, start in
        var frame = Data([
            1,
            UInt8(sequence >> 8),
            UInt8(sequence & 0xFF),
            UInt8(index),
            count,
        ])
        frame.append(payload[start ..< min(start + chunkSize, payload.count)])
        return frame
    }
}
