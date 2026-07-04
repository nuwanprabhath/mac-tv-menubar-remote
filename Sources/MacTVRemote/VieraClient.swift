import Foundation

/// Talks to a Panasonic VIERA TV over its SOAP/UPnP API on port 55000.
/// Uses the unencrypted protocol (pre-2018 models, e.g. DX640 series).
struct VieraClient: Sendable {
    let host: String

    enum Key: String {
        case play = "NRC_PLAY-ONOFF"
        case pause = "NRC_PAUSE-ONOFF"
        case stop = "NRC_STOP-ONOFF"
        case mute = "NRC_MUTE-ONOFF"
        case volumeUp = "NRC_VOLUP-ONOFF"
        case volumeDown = "NRC_VOLDOWN-ONOFF"
        case power = "NRC_POWER-ONOFF"
        case tv = "NRC_TV-ONOFF"
        case avInput = "NRC_CHG_INPUT-ONOFF"
        case enter = "NRC_ENTER-ONOFF"
        case digit0 = "NRC_D0-ONOFF"
        case digit1 = "NRC_D1-ONOFF"
        case digit2 = "NRC_D2-ONOFF"
        case digit3 = "NRC_D3-ONOFF"
        case digit4 = "NRC_D4-ONOFF"
        case digit5 = "NRC_D5-ONOFF"
        case digit6 = "NRC_D6-ONOFF"
        case digit7 = "NRC_D7-ONOFF"
        case digit8 = "NRC_D8-ONOFF"
        case digit9 = "NRC_D9-ONOFF"

        static func digit(_ character: Character) -> Key? {
            guard let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
            return Key(rawValue: "NRC_D\(value)-ONOFF")
        }
    }

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Remote key presses (NRC service)

    func send(_ key: Key) async throws {
        _ = try await soap(
            path: "nrc/control_0",
            urn: "panasonic-com:service:p00NetworkControl:1",
            action: "X_SendKey",
            body: "<X_KeyEvent>\(key.rawValue)</X_KeyEvent>"
        )
    }

    // MARK: - Volume / mute (standard UPnP RenderingControl)

    func getVolume() async throws -> Int {
        let xml = try await renderingControl("GetVolume")
        guard let v = firstMatch(in: xml, pattern: "<CurrentVolume>([0-9]+)</CurrentVolume>"),
              let vol = Int(v) else {
            throw APIError(message: "Unexpected GetVolume response")
        }
        return vol
    }

    func setVolume(_ volume: Int) async throws {
        _ = try await renderingControl("SetVolume", extra: "<DesiredVolume>\(max(0, min(100, volume)))</DesiredVolume>")
    }

    func getMute() async throws -> Bool {
        let xml = try await renderingControl("GetMute")
        guard let m = firstMatch(in: xml, pattern: "<CurrentMute>([01])</CurrentMute>") else {
            throw APIError(message: "Unexpected GetMute response")
        }
        return m == "1"
    }

    func setMute(_ muted: Bool) async throws {
        _ = try await renderingControl("SetMute", extra: "<DesiredMute>\(muted ? 1 : 0)</DesiredMute>")
    }

    /// Cheap reachability probe: succeeds only if a VIERA is answering on this host.
    func ping() async -> Bool {
        (try? await getVolume()) != nil
    }

    // MARK: - Plumbing

    private func renderingControl(_ action: String, extra: String = "") async throws -> String {
        try await soap(
            path: "dmr/control_0",
            urn: "schemas-upnp-org:service:RenderingControl:1",
            action: action,
            body: "<InstanceID>0</InstanceID><Channel>Master</Channel>" + extra
        )
    }

    private func soap(path: String, urn: String, action: String, body: String) async throws -> String {
        guard let url = URL(string: "http://\(host):55000/\(path)") else {
            throw APIError(message: "Bad host: \(host)")
        }
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:\(action) xmlns:u="urn:\(urn)">\(body)</u:\(action)></s:Body>
        </s:Envelope>
        """
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "POST"
        request.httpBody = envelope.data(using: .utf8)
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:\(urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")

        let (data, response) = try await URLSession.shared.data(for: request)
        let xml = String(data: data, encoding: .utf8) ?? ""
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError(message: "TV returned HTTP \(http.statusCode) for \(action)")
        }
        return xml
    }
}

func firstMatch(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}
