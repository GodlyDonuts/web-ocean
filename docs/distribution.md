# GitHub distribution

The first distributable is **v0.3.0-beta.2**, Apple silicon, macOS 26+. Consumers download a self-contained DMG, move/install the app to Applications and choose Use Ocean. There are no developer-tool or server requirements for users.

This is an **ad-hoc-signed, unnotarized community beta**. A development certificate is not a Developer ID distribution certificate. GitHub hosting does not remove Gatekeeper requirements. Release instructions explicitly disclose the first-launch warning and link to Apple’s per-app approval documentation; never recommend disabling Gatekeeper or removing quarantine attributes.

## Product flow

- The installer runs before wallpaper/network setup when launched outside Applications. It stages a complete app, refuses to replace unrelated apps, keeps an old Ocean app in the Trash and opens the installed copy. Only its own transient downloaded extension registration is removed, avoiding a wallpaper host pointing into a mounted disk image. If macOS still presents the relaunched copy at a temporary/translocated location, a one-shot relaunch flag directs the user to Finder rather than recursively reinstalling. No quarantine flags or security protections are changed.
- First launch offers Use Ocean, login choice and an approximate-location disclosure. Existing configured users migrate without repeating onboarding. A previously disabled app returns to welcome.
- Settings reopen from the menu bar or the app. Simple performance/daylight/weather controls have advanced options in a separate submenu.
- Explicit user pause is distinct from desktop coverage pause. The native host respects it on the lock screen and repaints one still frame if a new surface needs presentation.
- Manual weather previews are published to the shared environment, so desktop, screen saver and lock screen agree. Automatic weather remains the default.
- Turn Off Ocean waits for restoration results, disables login registration and quits after success. Failed restoration is reported; it does not claim success or discard appearance preferences.
- Help, privacy and third-party licenses are bundled offline. Support copying omits location/IP.

## Build a beta

```sh
zsh macos/build.sh
zsh macos/test-unit.sh
zsh macos/Tests/test-screensaver.sh
zsh macos/Tests/test-native-wallpaper.sh
python3 macos/Tests/verify_wallpaper_lifecycle.py
python3 tools/package-release.py --unsigned-beta --tag v0.3.0-beta.2
```

Commit source first. Packaging rejects dirty trees by default; `--allow-dirty` exists only for local review and marks the manifest accordingly. The app records hashes of its build inputs. Packaging rejects a stale app when those inputs change. Bundle versions must agree with each other and with the tag. The package includes Ocean.app, an Applications shortcut, a first-read help page and the MIT license. `.sha256` and `.json` sidecars identify the source commit and signing state.

Signing is inside-out, including the embedded saver and native extension with its existing sandbox entitlements. Hardened runtime and strict code-signature checks are applied. No broad code-loading exceptions are added. The DMG is verified after creation.

The `Build Ocean GitHub beta` workflow uses GitHub’s `macos-26` Apple silicon runner, builds/tests/packages, uploads artifacts and publishes a prerelease on a `v*-beta.*` tag. Manual dispatch builds artifacts without publishing. The ordinary validation workflow also uses macOS 26 for the native wallpaper SDK/runtime. Tagged release creation uses a notes file rather than shell-escaped prose.

Developer signing/notarization is optional future work: `--identity 'Developer ID Application: …' --notary-profile PROFILE` requires an existing certificate/profile, signs and notarizes the app and DMG, and staples both. Stable packages cannot use the unsigned-beta mode. No credentials are stored in the repository. Successful notarization with the private wallpaper compatibility layer has not been established; a script is not proof of Apple acceptance.

## Release checks and limits

Review the source and generated release notes, then tag the tested commit. Keep renderer regressions and actual native presentation checks separate from UI-only previews. The isolated ProductUIReview app has its own identifier and no embedded extensions or implementation of installer/weather/login actions, so reviewing settings cannot modify the live wallpaper. `--setup-preview` is also a developer-only UI preview path.

Require a read-only DMG mount/structure check and a post-update native executable-path check. Do not execute copied benchmark apps that still contain production wallpaper extensions: macOS can register them and select the wrong build. Keep copied diagnostic bundles isolated or strip their PlugIns directory.

Ad-hoc signing verifies package consistency, not publisher identity. Check the unsigned beta on a separate Mac/user with a quarantined browser download before calling clean-machine onboarding verified. Physical mixed-monitor/Space behavior, login registration on unsigned copies and OS-version compatibility need beta feedback. Public support is limited to the tested native-host generation rather than advertising the older developer fallback as a fully verified release target.

## Service and asset provenance

Weather attribution and CC BY 4.0 links are in Help. The current Open-Meteo endpoint is non-commercial; IPWhois terms and privacy also apply. Before commercializing or materially increasing usage, review service arrangements rather than embedding a shared API secret into a public binary. NASA/Gaia sky credits, the Aerial MIT license and the Ocean license ship inside Resources/Licenses. The app icon is original code-drawn artwork; `macos/Resources/MakeIcon.swift` regenerates the committed `.icns`.

[Getting started](getting-started.md) · [privacy](privacy.md) · [beta release notes](releases/BETA.md).
