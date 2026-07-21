import Foundation

// CLI escape hatches for testing the network layer without the GUI:
//   mac-tv-menubar-remote --discover           list VIERA TVs and Cast devices found via SSDP
//   mac-tv-menubar-remote --status [ip]        print volume/mute for a TV
//   mac-tv-menubar-remote --cast-status [ip]   print the Chromecast's media session
//   mac-tv-menubar-remote --cast-raw [ip]      dump the raw media session JSON (metadata shape)
//   mac-tv-menubar-remote --cast-seek <±s> [ip] seek the active cast session
let arguments = CommandLine.arguments

if arguments.contains("--discover") {
    runBlocking {
        let tvs = await Discovery.findTVs()
        if tvs.isEmpty {
            print("No VIERA TVs found.")
        }
        for tv in tvs {
            print("TV    \(tv.host)  \(tv.name)")
        }
        let casts = await Discovery.findCastDevices()
        for cast in casts {
            print("CAST  \(cast.host)  \(cast.name)")
        }
    }
} else if let index = arguments.firstIndex(of: "--cast-status") {
    runBlocking {
        var host = arguments.count > index + 1 ? arguments[index + 1] : ""
        if host.isEmpty {
            host = await Discovery.findCastDevices().first?.host ?? ""
        }
        guard !host.isEmpty else {
            print("No Cast device found or specified.")
            return
        }
        do {
            if let info = try await CastClient(host: host).mediaStatus() {
                let duration = info.duration.map { " duration=\($0)s remaining=\(Int(info.remaining ?? 0))s" } ?? ""
                print("Cast \(host): app=\(info.appName) title=\"\(info.displayTitle)\" state=\(info.playerState) position=\(info.currentTime)s\(duration)")
            } else {
                print("Cast \(host): idle (nothing casting)")
            }
        } catch {
            print("Cast \(host): error — \(error.localizedDescription)")
        }
    }
} else if let index = arguments.firstIndex(of: "--cast-raw") {
    runBlocking {
        var host = arguments.count > index + 1 ? arguments[index + 1] : ""
        if host.isEmpty {
            host = await Discovery.findCastDevices().first?.host ?? ""
        }
        guard !host.isEmpty else {
            print("No Cast device found or specified.")
            return
        }
        do {
            if let json = try await CastClient(host: host).rawMediaSessionJSON() {
                print(String(decoding: json, as: UTF8.self))
            } else {
                print("Cast \(host): idle (nothing casting)")
            }
        } catch {
            print("Cast \(host): error — \(error.localizedDescription)")
        }
    }
} else if let index = arguments.firstIndex(of: "--cast-seek") {
    runBlocking {
        guard arguments.count > index + 1, let delta = Double(arguments[index + 1]) else {
            print("Usage: --cast-seek <±seconds> [host]")
            return
        }
        var host = arguments.count > index + 2 ? arguments[index + 2] : ""
        if host.isEmpty {
            host = await Discovery.findCastDevices().first?.host ?? ""
        }
        guard !host.isEmpty else {
            print("No Cast device found or specified.")
            return
        }
        do {
            let position = try await CastClient(host: host).seek(by: delta)
            print("Cast \(host): seeked \(delta >= 0 ? "+" : "")\(Int(delta))s -> \(position)s")
        } catch {
            print("Cast \(host): error — \(error.localizedDescription)")
        }
    }
} else if let index = arguments.firstIndex(of: "--status") {
    runBlocking {
        var host = arguments.count > index + 1 ? arguments[index + 1] : ""
        if host.isEmpty {
            host = await Discovery.findTVs().first?.host ?? ""
        }
        guard !host.isEmpty else {
            print("No TV found or specified.")
            return
        }
        let client = VieraClient(host: host)
        do {
            let volume = try await client.getVolume()
            let muted = try await client.getMute()
            print("TV \(host): volume=\(volume) muted=\(muted)")
        } catch {
            print("TV \(host): error — \(error.localizedDescription)")
        }
    }
} else {
    RemoteApp.main()
}

func runBlocking(_ body: @escaping @Sendable () async -> Void) {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        await body()
        semaphore.signal()
    }
    semaphore.wait()
}
