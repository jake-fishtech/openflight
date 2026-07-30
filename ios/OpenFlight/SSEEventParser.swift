import Foundation

struct SSEEvent: Equatable {
    let name: String?
    let data: String
}

/// Incremental parser for the subset of Server-Sent Events OpenFlight uses:
/// `event:` and `data:` fields, comment lines used as heartbeats, and a blank
/// line to dispatch. Fed one line at a time so it can be driven by
/// `URLSession.AsyncBytes.lines` in the client and by literals in tests.
struct SSEEventParser {
    private var eventName: String?
    private var dataLines: [String] = []

    /// Feeds one line, returning an event when that line completes one.
    mutating func append(line: String) -> SSEEvent? {
        // AsyncLineSequence strips the newline but a CRLF stream can leave the
        // carriage return behind.
        let line = line.hasSuffix("\r") ? String(line.dropLast()) : line

        if line.isEmpty {
            return dispatch()
        }
        // A line beginning with a colon is a comment. The server sends these as
        // heartbeats so idle connections stay open and dead ones get noticed.
        guard !line.hasPrefix(":") else {
            return nil
        }

        let (field, value) = Self.split(line)
        switch field {
        case "event":
            eventName = value
        case "data":
            dataLines.append(value)
        default:
            // `id` and `retry` are unused, and unknown fields must be ignored.
            break
        }
        return nil
    }

    mutating func reset() {
        eventName = nil
        dataLines.removeAll(keepingCapacity: true)
    }

    private mutating func dispatch() -> SSEEvent? {
        defer { reset() }
        guard !dataLines.isEmpty else {
            return nil
        }
        return SSEEvent(name: eventName, data: dataLines.joined(separator: "\n"))
    }

    /// Splits `field: value`, dropping one optional space after the colon. A
    /// line with no colon is a field name with an empty value.
    private static func split(_ line: String) -> (field: String, value: String) {
        guard let colon = line.firstIndex(of: ":") else {
            return (line, "")
        }
        let field = String(line[line.startIndex ..< colon])
        var value = line[line.index(after: colon)...]
        if value.hasPrefix(" ") {
            value = value.dropFirst()
        }
        return (field, String(value))
    }
}
