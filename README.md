# Mihon TV — Mihon, adapted for Android TV

An Android TV adaptation of **[Mihon](https://github.com/mihonapp/mihon)**, forked from
[`mihonapp/mihon @ v0.20.4`](https://github.com/mihonapp/mihon/releases/tag/v0.20.4).

> [!NOTE]
> This is an **unofficial, personal fork** maintained for private use. It is not
> affiliated with, endorsed by, or supported by the Mihon project. Please **do not**
> report bugs from this build to the Mihon team — report them here instead.

## TV features (on top of stock Mihon)

| Area | What changed |
| --- | --- |
| Launcher | App appears on the Android TV home screen (`LEANBACK_LAUNCHER`) with a proper 320×180 TV banner; touchscreen no longer required to install |
| Focus | Visible D-pad focus indicator (accent border + subtle scale/highlight) replaces the touch ripple app-wide on TV |
| Navigation | Library / Updates / History / Browse / More rail is always visible and D-pad reachable |
| Screen changes | Focus is re-seeded into each pushed screen (Compose doesn't do this by itself) |
| Reader | **OK / center** opens the reader menu; menu controls become D-pad navigable; page turning via ← → ↑ ↓ already worked and is kept |
| Dialogs/sheets | Adaptive sheets use the centered layout on TV (no swipe-to-dismiss) |

Base Mihon features (extensions, downloads, tracking, backups, etc.) are untouched.

## Getting an APK

### From CI (easiest)

The **TV Fork Build** workflow runs on every push:

1. Open the repo on GitHub → **Actions** → **TV Fork Build** → latest run.
2. Download an artifact from the run summary:
   - `mihon-tv-arm64-v8a-release.apk` — most Android TVs (Shield TV, Chromecast w/ Google TV, Fire TV Stick 4K…)
   - `mihon-tv-universal-release.apk` — works on any device (larger download)
   - `mihon-tv-debug-apks` — debug build, package id `app.mihon.dev`, **installs side-by-side** with the official Mihon

APKs are signed with the default debug key, so no signing secrets are required.

### Build locally

Requirements: JDK 21 + Android SDK (or Android Studio), then:

```bash
./gradlew assembleDebug      # quick debug build (app.mihon.dev)
./gradlew assembleRelease    # minified release build
```

APKs land in `app/build/outputs/apk/{debug,release}/`.

## Installing on your TV

```bash
adb connect <tv-ip>:5555
adb install app-arm64-v8a-release.apk
```

Or put the APK on a USB drive / send it with an app like *Send files to TV*.
On the TV you may need to enable **Install unknown apps** for the installer you use.

## Syncing with upstream Mihon

```bash
git remote add upstream https://github.com/mihonapp/mihon.git
git fetch upstream
git merge --squash v0.20.5   # review changes
```

The fork's changes are deliberately small and live in a handful of files (search for
`isTvUi` / `isTelevision` / `TvFocusIndication`) so merges stay simple.

## License

This fork remains under the [Apache License 2.0](LICENSE), like Mihon itself. The Mihon
name/logo belong to their respective owners; attribution retained.
