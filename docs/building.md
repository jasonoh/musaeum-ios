# Building and pointing it at the Mac

> Moved verbatim from `README.md` when the README was cut down to a front page; headings were promoted one level and nothing else changed. The README keeps the short version.

## Build and run

```bash
xcodegen generate          # project.yml → Musaeum.xcodeproj (committed output; regenerate after adding a file)
open Musaeum.xcodeproj     # or, from the command line — the destination is an id, never a device name:
DEV=DE0B5601-7874-455E-A965-9AD80567C30E   # iPhone 17 Pro on iOS 26.1
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" build
xcodebuild -project Musaeum.xcodeproj -scheme Musaeum -destination "id=$DEV" test
```

Requires Xcode 27+, XcodeGen (`brew install xcodegen`), and **the Mac app running with its server switched on** (Settings → Phone access) for anything that touches the network.

## Unsigned build

Nothing here is set up to distribute: **no App Store, no TestFlight, no Ad Hoc or Enterprise profile, no notarisation.** This is an app built and run on one person's own simulator and phone — treat every build of it as unsigned, and as unsuitable for anyone else's device.

`project.yml` sets `CODE_SIGN_STYLE: Automatic` with a **free personal team** in `DEVELOPMENT_TEAM`, which is what lets a _device_ build get past _"Signing for Musaeum requires a development team"_; simulator builds ignore it. A free team grants no capabilities — and this app declares no entitlements, so it needs none. What it costs is that the profile it issues **expires after 7 days**: the app then refuses to launch until it is re-run once from Xcode. To build for your own device, put **your** team in `project.yml` and re-run `xcodegen generate`.

## Pointing it at the Mac

1. In Musaeum on the Mac: **Settings → Phone access**, turn it on. The row shows the URL to type into the phone and the bearer token beside it.
2. In this app: **Connect** — paste the URL and the token, then check the connection. The health payload names the contract version, the app version, the number of books and whether the library share is mounted.

The phone must be on the same tailnet as the Mac. The server binds the tailnet address only; there is no LAN or public surface.
