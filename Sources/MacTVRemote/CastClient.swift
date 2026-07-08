import Foundation
import Network

/// Snapshot of what's playing on a Google Cast device.
struct CastMediaStatus: Sendable {
    let appName: String
    let playerState: String // PLAYING / PAUSED / BUFFERING / IDLE
    let currentTime: Double
    let duration: Double? // total length in seconds; nil for live/unknown
    let mediaSessionId: Int

    var isActive: Bool { playerState != "IDLE" }
    var remaining: Double? { duration.map { max(0, $0 - currentTime) } }
}

enum CastError: LocalizedError {
    case timeout
    case connectionClosed
    case noApp
    case noMediaSession
    case badReply(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Chromecast did not reply in time"
        case .connectionClosed: return "Chromecast connection closed"
        case .noApp: return "Nothing is casting right now"
        case .noMediaSession: return "Cast app has no media session"
        case .badReply(let detail): return "Unexpected Chromecast reply: \(detail)"
        }
    }
}

/// Minimal Google Cast v2 client: TLS on port 8009 carrying protobuf-framed
/// JSON messages. Implements just enough (CONNECT / GET_STATUS / SEEK /
/// PLAY / PAUSE) for transport control — the same commands the Google Home
/// app's ±30s buttons send. No pairing or account auth is needed on the LAN.
struct CastClient: Sendable {
    let host: String

    /// Current media status, or nil when the device is idle / nothing casting.
    func mediaStatus() async throws -> CastMediaStatus? {
        try await withSession { session in
            try await session.fetchMediaStatus()?.status
        }
    }

    /// Seeks by `delta` seconds relative to the live position. Returns the new position.
    func seek(by delta: Double) async throws -> Double {
        try await withSession { session in
            guard let current = try await session.fetchMediaStatus() else { throw CastError.noApp }
            let target = max(0, current.status.currentTime + delta)
            let reply = try await session.mediaRequest(
                type: "SEEK", transportId: current.transportId,
                extra: ["mediaSessionId": current.status.mediaSessionId, "currentTime": target]
            )
            return Self.firstSession(in: reply)?["currentTime"].flatMap(Self.double) ?? target
        }
    }

    func setPlaying(_ play: Bool) async throws {
        _ = try await withSession { session in
            guard let current = try await session.fetchMediaStatus() else { throw CastError.noApp }
            return try await session.mediaRequest(
                type: play ? "PLAY" : "PAUSE", transportId: current.transportId,
                extra: ["mediaSessionId": current.status.mediaSessionId]
            )
        }
    }

    // MARK: - Session lifecycle

    private func withSession<T: Sendable>(_ body: @escaping @Sendable (CastSession) async throws -> T) async throws -> T {
        let session = CastSession(host: host)
        defer { session.close() }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await session.start()
                return try await body(session)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                throw CastError.timeout
            }
            defer {
                session.close() // unblocks a pending receive so the loser task ends
                group.cancelAll()
            }
            guard let result = try await group.next() else { throw CastError.timeout }
            return result
        }
    }

    static func firstSession(in payload: [String: Any]) -> [String: Any]? {
        (payload["status"] as? [[String: Any]])?.first
    }

    static func double(_ value: Any) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

/// Ensures a continuation is resumed exactly once across queue-hopping callbacks.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isSet { return false }
        isSet = true
        return true
    }
}

/// One TLS connection to a Cast device. Not reused across operations —
/// connect-per-action keeps state simple and costs well under a second.
final class CastSession: @unchecked Sendable {
    private static let nsConnection = "urn:x-cast:com.google.cast.tp.connection"
    private static let nsHeartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    private static let nsReceiver = "urn:x-cast:com.google.cast.receiver"
    private static let nsMedia = "urn:x-cast:com.google.cast.media"

    private let connection: NWConnection
    private var requestId = 0
    private var connectedTransports = Set<String>()

    init(host: String) {
        let tls = NWProtocolTLS.Options()
        // Cast devices present self-signed certificates; identity is the LAN address.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in
            complete(true)
        }, .global())
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: 8009),
            using: NWParameters(tls: tls)
        )
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = OnceFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.trySet() { cont.resume() }
                case .failed(let error):
                    if resumed.trySet() { cont.resume(throwing: error) }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
        try await send(source: "sender-0", dest: "receiver-0", namespace: Self.nsConnection, payload: ["type": "CONNECT"])
    }

    func close() {
        connection.cancel()
    }

    /// Receiver status -> running app -> media status for that app.
    /// Returns nil when the device shows only the idle Backdrop screen.
    func fetchMediaStatus() async throws -> (status: CastMediaStatus, transportId: String)? {
        let receiver = try await request(
            source: "sender-0", dest: "receiver-0", namespace: Self.nsReceiver,
            payload: ["type": "GET_STATUS"], expecting: "RECEIVER_STATUS"
        )
        let apps = (receiver["status"] as? [String: Any])?["applications"] as? [[String: Any]] ?? []
        guard let app = apps.first(where: { $0["transportId"] is String }),
              let transportId = app["transportId"] as? String,
              (app["isIdleScreen"] as? Bool) != true else {
            return nil
        }
        let appName = app["displayName"] as? String ?? "Cast"

        let media = try await mediaRequest(type: "GET_STATUS", transportId: transportId, extra: [:])
        guard let session = CastClient.firstSession(in: media),
              let mediaSessionId = session["mediaSessionId"] as? Int,
              let playerState = session["playerState"] as? String else {
            return nil
        }
        let mediaInfo = session["media"] as? [String: Any]
        let duration = mediaInfo?["duration"].flatMap(CastClient.double)
        let status = CastMediaStatus(
            appName: appName,
            playerState: playerState,
            currentTime: session["currentTime"].flatMap(CastClient.double) ?? 0,
            duration: (duration ?? 0) > 0 ? duration : nil,
            mediaSessionId: mediaSessionId
        )
        return (status, transportId)
    }

    func mediaRequest(type: String, transportId: String, extra: [String: Any]) async throws -> [String: Any] {
        if !connectedTransports.contains(transportId) {
            try await send(source: "sender-1", dest: transportId, namespace: Self.nsConnection, payload: ["type": "CONNECT"])
            connectedTransports.insert(transportId)
        }
        var payload: [String: Any] = ["type": type]
        payload.merge(extra) { _, new in new }
        return try await request(
            source: "sender-1", dest: transportId, namespace: Self.nsMedia,
            payload: payload, expecting: "MEDIA_STATUS"
        )
    }

    // MARK: - Request/response over the framed channel

    private func request(
        source: String, dest: String, namespace: String,
        payload: [String: Any], expecting: String
    ) async throws -> [String: Any] {
        requestId += 1
        let id = requestId
        var payload = payload
        payload["requestId"] = id
        try await send(source: source, dest: dest, namespace: namespace, payload: payload)

        while true {
            let (ns, message) = try await receiveMessage()
            if ns == Self.nsHeartbeat, message["type"] as? String == "PING" {
                try await send(source: "sender-0", dest: "receiver-0", namespace: Self.nsHeartbeat, payload: ["type": "PONG"])
                continue
            }
            let replyId = message["requestId"] as? Int
            let type = message["type"] as? String
            if type == expecting && (replyId == id || replyId == 0 || replyId == nil) {
                return message
            }
            if replyId == id {
                throw CastError.badReply(type ?? "unknown")
            }
        }
    }

    private func send(source: String, dest: String, namespace: String, payload: [String: Any]) async throws {
        let json = try JSONSerialization.data(withJSONObject: payload)
        var body = Data()
        body.append(Self.varintField(1, value: 0)) // protocol_version CASTV2_1_0
        body.append(Self.lengthField(2, bytes: Data(source.utf8)))
        body.append(Self.lengthField(3, bytes: Data(dest.utf8)))
        body.append(Self.lengthField(4, bytes: Data(namespace.utf8)))
        body.append(Self.varintField(5, value: 0)) // payload_type STRING
        body.append(Self.lengthField(6, bytes: json))

        var frame = Data()
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(body)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func receiveMessage() async throws -> (namespace: String, payload: [String: Any]) {
        let header = try await receiveExact(4)
        let length = header.withUnsafeBytes { $0.load(as: UInt32.self).byteSwapped }
        let body = try await receiveExact(Int(length))
        return try Self.parseMessage([UInt8](body))
    }

    private func receiveExact(_ count: Int) async throws -> Data {
        var buffer = Data()
        while buffer.count < count {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: count - buffer.count) { data, _, _, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        cont.resume(returning: data)
                    } else {
                        cont.resume(throwing: CastError.connectionClosed)
                    }
                }
            }
            buffer.append(chunk)
        }
        return buffer
    }

    // MARK: - Protobuf plumbing (CastMessage has only varint + length-delimited fields)

    private static func varint(_ value: Int) -> Data {
        var value = UInt64(value)
        var out = Data()
        repeat {
            let bits = UInt8(value & 0x7F)
            value >>= 7
            out.append(value != 0 ? bits | 0x80 : bits)
        } while value != 0
        return out
    }

    private static func varintField(_ number: Int, value: Int) -> Data {
        varint(number << 3 | 0) + varint(value)
    }

    private static func lengthField(_ number: Int, bytes: Data) -> Data {
        varint(number << 3 | 2) + varint(bytes.count) + bytes
    }

    private static func parseMessage(_ bytes: [UInt8]) throws -> (namespace: String, payload: [String: Any]) {
        var fields: [Int: [UInt8]] = [:]
        var pos = 0

        func decodeVarint() throws -> Int {
            var result = 0
            var shift = 0
            while true {
                guard pos < bytes.count else { throw CastError.badReply("truncated frame") }
                let byte = bytes[pos]
                pos += 1
                result |= Int(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
        }

        while pos < bytes.count {
            let key = try decodeVarint()
            let wireType = key & 7
            switch wireType {
            case 0:
                _ = try decodeVarint()
            case 2:
                let length = try decodeVarint()
                guard pos + length <= bytes.count else { throw CastError.badReply("truncated field") }
                fields[key >> 3] = Array(bytes[pos..<pos + length])
                pos += length
            default:
                throw CastError.badReply("wire type \(wireType)")
            }
        }

        let namespace = fields[4].map { String(decoding: $0, as: UTF8.self) } ?? ""
        var payload: [String: Any] = [:]
        if let raw = fields[6],
           let parsed = try? JSONSerialization.jsonObject(with: Data(raw)) as? [String: Any] {
            payload = parsed
        }
        return (namespace, payload)
    }
}
