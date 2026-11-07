# Getting started with Ocean

Ocean is a live ocean for your desktop, screen saver and lock screen. The first GitHub beta requires an Apple silicon Mac (M1 or newer) and macOS 26 or later.

## Install

1. Open [Ocean’s GitHub release page](https://github.com/GodlyDonuts/web-ocean/releases/tag/v0.3.0-beta.2).
2. Download **Ocean-…-arm64.dmg** under Assets. You do not need the Source code downloads.
3. Open the disk image and drag **Ocean** to **Applications**.
4. Open Ocean from Applications. Read the welcome screen and choose **Use Ocean**. Choose whether you want it to start at login.

Opening the app from the download instead offers **Install & Open**, which copies it to Applications for you. No administrator account is needed when installing in your own Applications folder; Ocean chooses that folder if the shared Applications folder is not writable.

**This beta is not Apple-notarized.** macOS may block the first launch because there is no Developer ID distribution certificate. Only approve a copy you trust from the official repository. Follow [Apple’s instructions for opening an unidentified developer’s app](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac). You do not need to disable Gatekeeper or run Terminal commands. Corporate-managed Macs may have policies that prevent this beta from running.

## Use Ocean

Click the wave icon in the menu bar and choose **Ocean Settings**. Opening Ocean again also opens settings. Closing settings keeps the wallpaper running.

- **Daylight:** follow local time or hold the scene at sunrise, midday, golden hour, sunset, midnight or a custom time. Waves and weather keep moving.
- **Weather:** follow local weather or choose a preview. Return to Follow Local Weather to use your area’s conditions again.
- **Performance:** Balanced adapts to your Mac. Save Energy reduces detail/frame rate; Sharper adds detail. Thermal and power limits still apply.
- **Start at login:** lets Ocean update your environment whenever you sign in. macOS may require approval in Login Items; Ocean offers to open that setting if needed.
- **Pause Animation:** pauses desktop and native lock-screen animation. New display/wake surfaces may need a single still frame to repaint.

Ocean uses approximate IP location without a GPS permission prompt. Internet/VPN location can be imprecise. Cached data and an offline fallback keep the scene working when services are unavailable. See [Privacy](privacy.md).

## Update

Use **Updates on GitHub** in settings. Download the new disk image, turn off Ocean, replace the app in Applications and open it again. The built-in Install & Open path can also update an installed copy. Previous app files are kept in the Trash during a built-in replacement. Preferences remain saved.

This beta does not silently download or run updates. Downloads and source tags are listed on GitHub. SHA-256 checksums and build manifests are provided for verification; they are not additional installers.

## Turn off or remove

Choose **Turn Off Ocean** in settings. Ocean restores the desktop/screen saver it replaced, disables Open at Login and quits. It preserves wallpaper choices you changed yourself afterward. Then move Ocean from Applications to the Trash if you want to uninstall it. Appearance preferences and local environment caches remain saved.

If restore fails, Ocean reports it instead of silently claiming success. You can repair setup or choose a wallpaper directly in macOS System Settings.

## Get help

Try **Repair Setup** if wallpaper selection needs attention after an update. **Copy Support Info** copies the app/macOS version and basic settings, without saved IP/coordinates. Paste it into a [GitHub issue](https://github.com/GodlyDonuts/web-ocean/issues) with what happened and, if useful, a screenshot. Nothing is submitted automatically.

Native wallpaper integration depends on macOS compatibility interfaces. Live lock/wake behavior has been tested on the development Mac; mixed displays, Spaces and fresh Macs need wider beta feedback. This beta is an idealized cinematic ocean, not a marine forecast.
