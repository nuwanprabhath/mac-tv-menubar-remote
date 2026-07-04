# Changelog

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
