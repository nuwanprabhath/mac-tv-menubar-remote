# mac-tv-menubar-remote

A native macOS menu bar remote for Panasonic VIERA TVs (unencrypted protocol, pre-2018 models such as the DX640 series). Play, pause, stop, mute, set volume, and power off the TV from a dropdown in the menu bar.

<p align="center">
  <img src="docs/screenshot.png" alt="TV Menubar Remote popover showing playback controls, volume slider, TV/AV/channel controls, and power off" width="320">
</p>

## Features

- **Auto-discovery**: finds the TV via SSDP (`ssdp:all` M-SEARCH, filtered to the VIERA `/nrc/ddd.xml` descriptor), so it keeps working when the TV's IP changes. Last known address is cached for instant startup and re-discovery only happens when the TV stops answering.
- **Absolute volume slider** backed by UPnP RenderingControl `GetVolume`/`SetVolume` (debounced), with live volume/mute state synced every time the popover opens.
- **Transport keys** (play/pause/stop) and power-off via Panasonic's `X_SendKey` SOAP action on port 55000.
- Ships as a proper `.app` with `LSUIElement` — menu bar only, no Dock icon.

## Build & install

```sh
./build.sh
open "dist/TV Menubar Remote.app"          # run it
cp -R "dist/TV Menubar Remote.app" /Applications/   # install
```

To start at login: System Settings → General → Login Items → add the app.

## CLI test flags

The same binary doubles as a network-layer test tool:

```sh
.build/release/MacTVRemote --discover      # list VIERA TVs on the LAN
.build/release/MacTVRemote --status [ip]   # print volume/mute state
```

## Notes

- **Power on doesn't work** once the TV is fully off — the DX640 shuts down its network interface in standby (unless the TV's networked-standby setting is enabled). Power *off* works.
- macOS may show a **Local Network permission** prompt on first launch (needed for SSDP multicast and talking to the TV) — allow it.
- Protocol details: SOAP over HTTP to `http://<tv>:55000/nrc/control_0` (key presses, `urn:panasonic-com:service:p00NetworkControl:1#X_SendKey`) and `/dmr/control_0` (volume/mute, standard `RenderingControl:1`). No pairing or encryption is required on this model generation; 2018+ models would need the encrypted pairing handshake, which this app does not implement.
