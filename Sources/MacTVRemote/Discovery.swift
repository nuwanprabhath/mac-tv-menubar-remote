import Foundation

struct DiscoveredTV: Sendable, Equatable {
    let host: String
    let name: String
}

/// Finds Panasonic VIERA TVs on the LAN.
///
/// Primary path is an SSDP `M-SEARCH` broadcast. The DX640 ignores queries
/// targeted at its Panasonic service URN but answers `ssdp:all`, so we ask for
/// everything and keep responders whose LOCATION is the VIERA network-remote
/// descriptor (`/nrc/ddd.xml`).
enum Discovery {
    static func findTVs(timeout: TimeInterval = 2.5) async -> [DiscoveredTV] {
        await resolve(candidates: ssdpSearchAsync(timeout: timeout).filter {
            $0.location.lowercased().hasSuffix("/nrc/ddd.xml")
        })
    }

    /// Google Cast devices (Chromecast etc.). They answer the same SSDP
    /// broadcast, advertising their DIAL descriptor on port 8008.
    static func findCastDevices(timeout: TimeInterval = 2.5) async -> [DiscoveredTV] {
        await resolve(candidates: ssdpSearchAsync(timeout: timeout).filter {
            $0.location.contains(":8008/")
        })
    }

    private static func ssdpSearchAsync(timeout: TimeInterval) async -> [(host: String, location: String)] {
        await Task.detached(priority: .userInitiated) {
            ssdpSearch(timeout: timeout)
        }.value
    }

    private static func resolve(candidates: [(host: String, location: String)]) async -> [DiscoveredTV] {
        var devices: [DiscoveredTV] = []
        for (host, location) in candidates {
            let name = await friendlyName(descriptorURL: location) ?? host
            devices.append(DiscoveredTV(host: host, name: name))
        }
        return devices
    }

    /// Blocking SSDP search over a plain BSD UDP socket.
    /// Returns every unique (host, descriptor URL) pair that responds; callers filter.
    private static func ssdpSearch(timeout: TimeInterval) -> [(host: String, location: String)] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var recvTimeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(1900).bigEndian
        dest.sin_addr.s_addr = inet_addr("239.255.255.250")

        let msearch = [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: 2",
            "ST: ssdp:all",
            "", ""
        ].joined(separator: "\r\n")

        let sent = msearch.withCString { ptr in
            withUnsafePointer(to: &dest) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, ptr, strlen(ptr), 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return [] }

        var found: [String: String] = [:]
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buffer, buffer.count, 0, sa, &fromLen)
                }
            }
            guard n > 0 else { continue }

            let text = String(decoding: buffer[0..<n], as: UTF8.self)
            guard let location = firstMatch(in: text, pattern: "(?im)^location:\\s*(\\S+)") else { continue }
            let host = String(cString: inet_ntoa(from.sin_addr))
            // Keyed by location: one device advertises several descriptors,
            // and callers pick the one they recognize.
            found[location] = host
        }

        return found.map { (host: $0.value, location: $0.key) }.sorted { $0.host < $1.host }
    }

    /// Reads the TV's friendly name (e.g. "55DX640_Series") from its UPnP descriptor.
    static func friendlyName(descriptorURL: String) async -> String? {
        guard let url = URL(string: descriptorURL) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let xml = String(data: data, encoding: .utf8) else { return nil }
        return firstMatch(in: xml, pattern: "<friendlyName>([^<]+)</friendlyName>")
    }
}
