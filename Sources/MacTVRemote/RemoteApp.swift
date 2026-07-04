import SwiftUI

struct RemoteApp: App {
    @StateObject private var tv = TVController()

    var body: some Scene {
        MenuBarExtra("TV Remote", systemImage: "tv") {
            RemoteView()
                .environmentObject(tv)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RemoteView: View {
    @EnvironmentObject private var tv: TVController
    @State private var channelInput = ""

    var body: some View {
        VStack(spacing: 12) {
            header

            HStack(spacing: 10) {
                TransportButton(symbol: "play.fill", help: "Play") { tv.press(.play) }
                TransportButton(symbol: "pause.fill", help: "Pause") { tv.press(.pause) }
                TransportButton(symbol: "stop.fill", help: "Stop") { tv.press(.stop) }
                TransportButton(
                    symbol: tv.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    help: tv.isMuted ? "Unmute" : "Mute",
                    isActive: tv.isMuted
                ) { tv.toggleMute() }
            }

            HStack(spacing: 8) {
                Button {
                    tv.stepVolume(by: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .disabled(tv.volume <= 0)
                .help("Volume down")

                VolumeTrack(value: $tv.volume) { newValue in
                    tv.volumeChanged(to: newValue)
                }

                Button {
                    tv.stepVolume(by: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .disabled(tv.volume >= 100)
                .help("Volume up")

                Text("\(Int(tv.volume))")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 24, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                Button("TV") { tv.press(.tv) }
                    .buttonStyle(.bordered)
                    .help("Switch to TV tuner")
                Button("AV") { tv.press(.avInput) }
                    .buttonStyle(.bordered)
                    .help("Cycle AV input")

                TextField("Channel", text: $channelInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .onChange(of: channelInput) { newValue in
                        channelInput = String(newValue.filter(\.isNumber).prefix(4))
                    }
                    .onSubmit { goToChannel() }
                Button {
                    goToChannel()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(channelInput.isEmpty ? .tertiary : .primary)
                .disabled(channelInput.isEmpty)
                .help("Go to channel")
            }

            Divider()

            Button(role: tv.status == .connected ? .destructive : nil) {
                tv.togglePower()
            } label: {
                Label(
                    tv.status == .connected ? "Power Off TV" : "Power On TV",
                    systemImage: "power"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            if let error = tv.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Divider()

            HStack {
                Button("Find TV") { Task { await tv.discover() } }
                    .disabled(tv.status == .searching)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
        .task {
            await tv.refresh()
        }
    }

    private func goToChannel() {
        guard !channelInput.isEmpty else { return }
        tv.enterChannel(channelInput)
        channelInput = ""
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(tv.deviceName)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if tv.status == .searching {
                ProgressView()
                    .controlSize(.small)
            } else if !tv.host.isEmpty {
                Text(tv.host)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var statusColor: Color {
        switch tv.status {
        case .connected: .green
        case .searching: .yellow
        case .unreachable: .red
        case .unknown: .gray
        }
    }
}

/// A minimal capsule volume track — avoids the faint secondary groove line
/// AppKit's native `Slider` renders against the popover's vibrant background.
private struct VolumeTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double> = 0...100
    let onChange: (Double) -> Void

    private let trackHeight: CGFloat = 4
    private let thumbDiameter: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let fillWidth = max(0, min(width, width * fraction))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: fillWidth, height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: fillWidth - thumbDiameter / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in set(from: drag.location.x, width: width) }
            )
        }
        .frame(height: thumbDiameter)
    }

    private func set(from x: CGFloat, width: CGFloat) {
        let fraction = max(0, min(1, x / width))
        let newValue = (range.lowerBound + fraction * (range.upperBound - range.lowerBound)).rounded()
        guard newValue != value else { return }
        value = newValue
        onChange(newValue)
    }
}

private struct TransportButton: View {
    let symbol: String
    let help: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 30)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .accentColor : nil)
        .help(help)
    }
}
