import Foundation

// CLI escape hatches for testing the network layer without the GUI:
//   mac-tv-menubar-remote --discover      list VIERA TVs found via SSDP
//   mac-tv-menubar-remote --status [ip]   print volume/mute for a TV
let arguments = CommandLine.arguments

if arguments.contains("--discover") {
    runBlocking {
        let tvs = await Discovery.findTVs()
        if tvs.isEmpty {
            print("No VIERA TVs found.")
        }
        for tv in tvs {
            print("\(tv.host)  \(tv.name)")
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
