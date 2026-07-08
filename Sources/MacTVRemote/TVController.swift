import Foundation
import SwiftUI

@MainActor
final class TVController: ObservableObject {
    enum Status: Equatable {
        case unknown
        case searching
        case connected
        case unreachable
    }

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "tvHost") }
    }
    @Published var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "tvName") }
    }
    @Published var status: Status = .unknown
    @Published var volume: Double = 0
    @Published var isMuted = false
    @Published var lastError: String?

    @Published var castHost: String? {
        didSet { UserDefaults.standard.set(castHost, forKey: "castHost") }
    }
    @Published var castName: String? {
        didSet { UserDefaults.standard.set(castName, forKey: "castName") }
    }
    /// Live media session on the Chromecast, nil when nothing is casting.
    @Published var castInfo: CastMediaStatus? {
        didSet { castInfoDate = Date() }
    }
    /// When `castInfo` was fetched — lets the UI tick the position forward
    /// locally while playing, without polling the Chromecast.
    private(set) var castInfoDate = Date()

    /// Playback position extrapolated to `date` (frozen while paused/buffering).
    func castPosition(at date: Date) -> Double? {
        guard let info = castInfo else { return nil }
        guard info.playerState == "PLAYING" else { return info.currentTime }
        let position = info.currentTime + date.timeIntervalSince(castInfoDate)
        return info.duration.map { min(position, $0) } ?? position
    }

    private var client: VieraClient { VieraClient(host: host) }
    private var volumeSetTask: Task<Void, Never>?
    /// Suppresses slider onChange feedback while we apply TV state to the UI.
    private var applyingRemoteState = false

    init() {
        host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
        deviceName = UserDefaults.standard.string(forKey: "tvName") ?? "No TV configured"
        castHost = UserDefaults.standard.string(forKey: "castHost")
        castName = UserDefaults.standard.string(forKey: "castName")
    }

    /// Called when the menu bar popover opens: sync UI with the TV,
    /// re-discovering it if the cached address no longer answers.
    func refresh() async {
        lastError = nil
        let castJob = Task { await refreshCast() }
        defer { _ = castJob }
        if host.isEmpty {
            await discover()
            return
        }
        if await pullState() { return }
        await discover()
    }

    func discover() async {
        status = .searching
        lastError = nil
        let tvs = await Discovery.findTVs()
        guard let tv = tvs.first else {
            status = host.isEmpty ? .unknown : .unreachable
            lastError = "No VIERA TV found on the network. Is the TV on?"
            return
        }
        host = tv.host
        deviceName = tv.name
        _ = await pullState()
        if castHost == nil { await discoverCast() }
    }

    // MARK: - Chromecast

    func discoverCast() async {
        guard let device = await Discovery.findCastDevices().first else { return }
        castHost = device.host
        castName = device.name
    }

    func refreshCast() async {
        if castHost == nil { await discoverCast() }
        guard let host = castHost else {
            castInfo = nil
            return
        }
        do {
            castInfo = try await CastClient(host: host).mediaStatus()
        } catch {
            // Device unreachable — its IP may have changed; rediscover once.
            castInfo = nil
            await discoverCast()
            if let newHost = castHost, newHost != host {
                castInfo = try? await CastClient(host: newHost).mediaStatus()
            }
        }
    }

    /// Seek the active cast session by ±seconds (Netflix etc. via Chromecast).
    /// The TV itself has no working seek path, so this is cast-only.
    func skipCast(by delta: Double) {
        guard let host = castHost, castInfo?.isActive == true else {
            lastError = "Skip needs an active cast session (e.g. Netflix on the Chromecast)."
            return
        }
        Task {
            do {
                let position = try await CastClient(host: host).seek(by: delta)
                lastError = nil
                if var info = castInfo {
                    info = CastMediaStatus(
                        appName: info.appName, playerState: info.playerState,
                        currentTime: position, duration: info.duration,
                        mediaSessionId: info.mediaSessionId
                    )
                    castInfo = info
                }
            } catch {
                lastError = "Seek failed: \(error.localizedDescription)"
                await refreshCast()
            }
        }
    }

    /// Play/pause routed to the Chromecast when it has an active session
    /// (direct and reliable), falling back to the TV key (HDMI-CEC hop) otherwise.
    func playPause(_ play: Bool) {
        if let host = castHost, castInfo?.isActive == true {
            Task {
                do {
                    try await CastClient(host: host).setPlaying(play)
                    lastError = nil
                    await refreshCast()
                } catch {
                    press(play ? .play : .pause)
                }
            }
        } else {
            press(play ? .play : .pause)
        }
    }

    @discardableResult
    private func pullState() async -> Bool {
        guard !host.isEmpty else { return false }
        do {
            let vol = try await client.getVolume()
            let muted = try await client.getMute()
            applyingRemoteState = true
            volume = Double(vol)
            isMuted = muted
            applyingRemoteState = false
            status = .connected
            return true
        } catch {
            status = .unreachable
            return false
        }
    }

    func press(_ key: VieraClient.Key) {
        run { try await self.client.send(key) }
    }

    func toggleMute() {
        let target = !isMuted
        isMuted = target
        run {
            try await self.client.setMute(target)
        }
    }

    /// Debounced absolute volume set, driven by the slider.
    func volumeChanged(to value: Double) {
        guard !applyingRemoteState else { return }
        volumeSetTask?.cancel()
        volumeSetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled else { return }
            self.run { try await self.client.setVolume(Int(value.rounded())) }
        }
    }

    /// Steps volume up/down by one, e.g. from the +/- buttons. Goes through
    /// the same path as the slider so both stay in sync.
    func stepVolume(by delta: Int) {
        volume = Double(min(100, max(0, Int(volume.rounded()) + delta)))
        volumeChanged(to: volume)
    }

    /// Tunes to a channel by sending its digits as key presses, then Enter.
    /// The gaps mimic pressing the buttons on the physical remote.
    func enterChannel(_ number: String) {
        let digits = number.filter(\.isNumber)
        let keys = digits.compactMap { VieraClient.Key.digit($0) }
        guard !keys.isEmpty, keys.count == digits.count, digits.count <= 4 else {
            lastError = "Channel must be 1–4 digits."
            return
        }
        run {
            for key in keys {
                try await self.client.send(key)
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            try await self.client.send(.enter)
        }
    }

    /// Same physical key both ways: `NRC_POWER-ONOFF` toggles standby. When the
    /// TV is already unreachable we're attempting to wake it, so re-check its
    /// real state afterwards rather than assuming the toggle direction. Bypasses
    /// the generic `run` helper, which would otherwise stomp the status we set
    /// here by forcing it back to `.connected` on any successful send.
    func togglePower() {
        let wasReachable = status == .connected
        Task {
            do {
                try await client.send(.power)
                lastError = nil
                if wasReachable {
                    status = .unreachable
                } else {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    _ = await pullState()
                }
            } catch {
                status = .unreachable
                lastError = error.localizedDescription
            }
        }
    }

    private func run(_ operation: @escaping @Sendable () async throws -> Void) {
        Task {
            do {
                try await operation()
                if status != .connected { status = .connected }
                lastError = nil
            } catch {
                status = .unreachable
                lastError = error.localizedDescription
            }
        }
    }
}
