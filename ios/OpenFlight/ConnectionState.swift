import Foundation

/// Connection status shared by every shot transport, so the dashboard renders
/// Bluetooth and Wi-Fi with one code path.
enum ConnectionState: Equatable {
    case idle
    case unavailable(String)
    case scanning
    case connecting
    case discovering
    case connected
    case error(String)

    var description: String {
        switch self {
        case .idle:
            "Ready"
        case let .unavailable(message), let .error(message):
            message
        case .scanning:
            "Looking for OpenFlight"
        case .connecting:
            "Connecting"
        case .discovering:
            "Preparing shot notifications"
        case .connected:
            "Connected"
        }
    }

    var canRetry: Bool {
        switch self {
        case .idle, .unavailable, .error:
            true
        default:
            false
        }
    }
}
