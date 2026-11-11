# Deskland Preview for macOS

An AppKit host that puts the Beach and Meadow theme pages in a desktop-level window behind your icons and reshapes the scenery around the real icon positions. It runs the same `prototype/` pages as the Windows host, with the same `chrome.webview` message protocol.

## Requirements

- macOS 15 or later, Apple silicon or Intel.
- Swift 6 toolchain (Xcode or the Command Line Tools).
- [Task](https://taskfile.dev) and `jq` to build the app. ImageMagick is only needed to regenerate the icon.
- Main display only. Icon positions are read from Finder through the Accessibility API.

## Build and run

```sh
task macos:test      # swift test
task macos:build     # universal DMG in macos/dist/
```

`task macos:build` builds an arm64 + x86_64 binary, assembles `Deskland Preview.app`, signs it, wraps it in a DMG, notarizes and staples it, and writes a `.sha256` and a `.manifest.json` next to the DMG. It does nothing when the inputs and signing setup are unchanged; pass `-f` to force a rebuild. The shipped files come from `tools/ship-files.txt`, the same list the Windows installer reads.

For a quick run without a bundle, build from `macos/` so the linker embeds `Info.plist`:

```sh
cd macos && swift run DesklandMac
```

A bare binary inherits Terminal's Accessibility grant, and launch at login only works from the app bundle.

Command-line flags go to the running instance, or start one if none is running:

| Flag | Behavior |
| --- | --- |
| none | Start the wallpaper and open settings; opens settings when already running |
| `--autostart` | Start in the background without settings |
| `--settings` | Open settings |
| `--menu` | Open the status menu |
| `--exit` | Quit and remove the wallpaper |

```sh
"/Applications/Deskland Preview.app/Contents/MacOS/DesklandMac" --exit
```

## Signing and notarization

Copy `.env.example` to `.env` in the repository root; it is gitignored and `task` loads it.

| Variable | Purpose |
| --- | --- |
| `APPLE_SIGNING_IDENTITY` | Developer ID Application identity in the login keychain. Unset signs ad-hoc with a warning and skips notarization |
| `NOTARY_PROFILE` | `notarytool` keychain profile. Wins over the API key |
| `APPLE_API_KEY`, `APPLE_API_ISSUER`, `APPLE_API_KEY_B64` | App Store Connect API key ID, issuer and the base64 of the `.p8`. The key is written to a 0600 temporary file that is deleted afterwards |

With neither a profile nor a complete API key, notarization is skipped with a message. The app uses the hardened runtime and is not sandboxed.

A signed build can be checked with:

```sh
xcrun stapler validate macos/dist/*.dmg
spctl -a -t open --context context:primary-signature -vv macos/dist/*.dmg
```

## Permissions

Deskland needs one permission, **Accessibility**, to read desktop icon positions from Finder.

1. On first launch the system prompt appears once; choose **Allow**. A marker file, `accessibility.prompted`, in the data directory stops it from appearing again.
2. Until access is granted the wallpaper runs without icon adaptation. The app picks the grant up without a relaunch.
3. To grant or revoke it later, use the toggle for Deskland Preview in System Settings → Privacy & Security → Accessibility.
4. The status menu entry **Grant Accessibility access…** opens that pane and shows a check mark once access is granted.

To start over, run `tccutil reset Accessibility app.deskland.preview` and delete `accessibility.prompted`.

The Ctrl+Option+H hotkey uses Carbon and needs no permission.

## Unsigned and ad-hoc builds

A build without a Developer ID signature is blocked by Gatekeeper on first launch. Open it anyway:

1. Try to open `Deskland Preview.app` once and dismiss the warning.
2. Open System Settings → Privacy & Security, scroll to the message about Deskland Preview and click **Open Anyway**.
3. Confirm with your password.

Or remove the quarantine flag from a downloaded copy: `xattr -dr com.apple.quarantine "Deskland Preview.app"`.

## Behavior and data

- The status item is a leaf icon with Settings, Pause animation, Reload, Start at login, Grant Accessibility access and Exit. Ctrl+Option+H opens the menu at the pointer.
- The app has no Dock icon.
- The wallpaper pauses for a fullscreen or maximized frontmost window, a fullscreen Space, display sleep or a locked screen, and resumes when they end. It can also be paused from the menu.
- Settings and logs are stored in `~/Library/Application Support/DesklandPreview`, with `host.log` and `settings.json` there. Shared images and videos go to `~/Pictures/Deskland Preview`.
- Set `DESKLAND_PROFILE_DIR` to an absolute path to isolate settings, caches and the single-instance lock. Set `DESKLAND_PAGE_DIR` to serve theme pages from another directory.
- Changes to theme pages need the menu's Reload; Swift changes need a rebuild.
- English and Simplified Chinese only. There is no sign-in, purchase restore or update check.

## Known limitations

- **Stage Manager is untested and unsupported.** How the desktop-level window and icon tracking behave with it enabled is unknown.
- Main display only.
- The Accessibility grant without relaunch and launch at login have not yet been verified from a built app bundle; TASK-004.01 tracks both.
