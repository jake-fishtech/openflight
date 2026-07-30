import Foundation

enum WiFiShotError: LocalizedError, Equatable {
    case invalidHost(String)
    case unexpectedStatus(Int)
    case streamEnded

    var errorDescription: String? {
        switch self {
        case let .invalidHost(host):
            host.isEmpty
                ? "Enter the address of your OpenFlight Pi."
                : "\"\(host)\" is not a valid address."
        case let .unexpectedStatus(code):
            code == 503
                ? "Too many devices are streaming shots."
                : "OpenFlight returned HTTP \(code)."
        case .streamEnded:
            "OpenFlight closed the connection."
        }
    }
}

/// Receives shots over Wi-Fi from the Pi's Server-Sent Events endpoint.
///
/// The Wi-Fi sibling of `BluetoothManager`: same published surface, same shared
/// decoder, so the dashboard does not care which transport is in use. Useful on
/// hardware where BLE advertising is unavailable, and for verifying the payload
/// with `curl` before involving a phone at all.
@MainActor
final class WiFiShotClient: ObservableObject {
    /// Raspberry Pi OS publishes its hostname over mDNS, so the default works
    /// on a stock install and survives DHCP changes. Rename the Pi and this
    /// becomes `<hostname>.local`.
    static let defaultHost = "raspberrypi.local:8080"
    static let defaultPort = 8080
    static let streamPath = "/api/shots/stream"

    /// Three missed 15-second heartbeats before a silent connection is retried.
    static let idleTimeout: TimeInterval = 45
    static let initialReconnectDelay: Duration = .seconds(1)
    static let maximumReconnectDelay: Duration = .seconds(15)

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var latestShot: ShotEvent?

    private let session: URLSession
    private var streamTask: Task<Void, Never>?
    private var parser = SSEEventParser()
    private var decoder = ShotEventDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Builds the stream URL from whatever the user typed: a bare hostname, a
    /// host and port, or a full URL. Returns `nil` when it cannot be used.
    static func streamURL(host: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let absolute = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: absolute),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }

        components.scheme = scheme
        if components.port == nil, scheme == "http" {
            components.port = defaultPort
        }
        components.path = streamPath
        components.query = nil
        components.fragment = nil
        return components.url
    }

    func start(host: String) {
        guard let url = Self.streamURL(host: host) else {
            streamTask?.cancel()
            streamTask = nil
            state = .error(
                WiFiShotError.invalidHost(host).localizedDescription
            )
            return
        }
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            await self?.run(url: url)
        }
    }

    func retry(host: String) {
        disconnect()
        start(host: host)
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        parser.reset()
        decoder.reset()
        state = .idle
    }

    /// Handles one parsed event. Separate from the network loop so delivery and
    /// de-duplication can be tested without a server.
    func receive(_ event: SSEEvent) {
        guard event.name == nil || event.name == "shot" else { return }
        do {
            guard let shot = try decoder.decode(Data(event.data.utf8)) else { return }
            latestShot = shot
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func run(url: URL) async {
        var reconnectDelay = Self.initialReconnectDelay

        while !Task.isCancelled {
            do {
                try await connect(to: url)
                reconnectDelay = Self.initialReconnectDelay
                throw WiFiShotError.streamEnded
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(error.localizedDescription)
                try? await Task.sleep(for: reconnectDelay)
                reconnectDelay = min(reconnectDelay * 2, Self.maximumReconnectDelay)
            }
        }
    }

    private func connect(to url: URL) async throws {
        state = .connecting
        parser.reset()

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.idleTimeout

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WiFiShotError.unexpectedStatus(http.statusCode)
        }
        state = .connected

        for try await line in bytes.lines {
            guard !Task.isCancelled else { return }
            if let event = parser.append(line: line) {
                receive(event)
            }
        }
    }
}
