# Changelog

## 0.3.2 — 2026-07-08

- Cast timing now ticks live: the position extrapolates locally once per second from the last Chromecast snapshot while playing (frozen while paused), with no extra network polling.

## 0.3.1 — 2026-07-08

- Cast row now shows episode timing: elapsed / total plus time remaining, read from the Cast media session's `media.duration`.
- Volume row is symmetric: the numeric readout moved from the row's end to a small label centered under the slider, so the −/+ buttons mirror each other.

## 0.3.0 — 2026-07-08

- **±30s skip buttons** via the Google Cast protocol: a dependency-free Cast v2 client (TLS on port 8009, protobuf-framed JSON) sends `SEEK` to the Chromecast's live media session — the same command behind the Google Home app's skip buttons. Works with Netflix and anything else that casts.
- Cast session status shown between the skip buttons (app name + player state); buttons disable when nothing is casting.
- Play/pause now route to the Chromecast when a cast session is active (direct and reliable), falling back to the TV key (HDMI-CEC hop) otherwise.
- Chromecast auto-discovery over SSDP with cached address and rediscovery when it stops answering. Fixed the SSDP collector discarding non-VIERA responders.
- New CLI flags: `--cast-status [ip]` and `--cast-seek <±seconds> [ip]`; `--discover` now lists Cast devices too.

## 0.2.3 — 2026-07-04

- Replaced the native `Slider` for volume with a custom-drawn capsule track, removing the faint secondary groove line AppKit renders under sliders on translucent/vibrant backgrounds like the menu bar popover.

## 0.2.2 — 2026-07-04

- Added +/- buttons flanking the volume slider for single-step adjustments, sharing the same debounced `setVolume` path as the slider so they can't race each other.

## 0.2.1 — 2026-07-04

- The power button now reads "Power On TV" when the TV is off/unreachable and "Power Off TV" when connected, instead of always saying "Power Off". Fixed a status bug where a successful key send always forced status back to `.connected`, which would have masked the off state right after toggling.

## 0.2.0 — 2026-07-04

- TV / AV buttons: switch back to the tuner (`NRC_TV-ONOFF`) or cycle AV inputs (`NRC_CHG_INPUT-ONOFF`).
- Channel number entry (1–4 digits): sends digit key presses followed by Enter, like typing on the physical remote. Submit with the ⏎ key or the arrow button.

## 0.1.0 — 2026-07-04

- Initial release: SwiftUI `MenuBarExtra` app for Panasonic VIERA TVs (unencrypted protocol).
- Play / pause / stop / mute toggle via `X_SendKey`.
- Absolute volume slider with live state sync via UPnP RenderingControl.
- Power off button.
- SSDP auto-discovery with cached-IP fast path and `--discover` / `--status` CLI test flags.
- `build.sh` assembles a signed (ad-hoc) menu-bar-only `.app` bundle.
