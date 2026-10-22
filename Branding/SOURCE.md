# Branding sources

The app icon and logo are the web app's own artwork, taken **unchanged** from the
old web tree at commit `a3c86df0436a3eedc341ab5163fc5ee6b1688b5d` (also on
`archive/webapp-main-before-native-2026-10-22`).

| file | origin in that commit | handling |
|---|---|---|
| `appicon.png` | `public/assets/appicon.png` | copied byte for byte; 1024×1024, already opaque, used as `iconPath` |
| `monochrome_icon.svg` | `images/monochrome_icon.svg` | copied byte for byte; vector source of the icon |
| `monochrome_logo.svg` | `images/monochrome_logo.svg` | copied byte for byte; the logo used in the web UI |
| `monochrome_logo.png` | rasterised from `monochrome_logo.svg` | 512×512 RGBA, the only change is rasterisation: SwiftUI cannot draw SVG |

Nothing was redrawn, recoloured, cropped, re-margined, given effects, or given
pre-rounded corners; iOS applies its own icon mask. `appicon.png` is used as the
app icon without any conversion, and it is already fully opaque, so no
flattening was needed.

The SVGs are stored next to the raster so the artwork can be regenerated if a
larger size is ever needed.

## Licence and attribution

The Monochrome repository is Apache-2.0 (its `license` file), which covers the
source code of that project. The icon and logo are the project's branding; this
fork is a personal, non-distributed build that reuses them for the same
application. Do not redistribute the artwork outside this context without
checking with the upstream project.

## Packaging status

`the local xtool manifest` uses `iconPath: Branding/appicon.png`. The schema
(`Sources/PackLib/PackSchema.swift` in xtool 1.22.2's source) accepts
`iconPath` and requires a `.png` extension, which matches. Packing an `.app`
needs `xtool dev`, which also installs to a device and is forbidden here, so
"the icon appears on the Home Screen" is **unverified (L4)** and remains on the
device checklist.
