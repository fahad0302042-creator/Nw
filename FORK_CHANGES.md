# Nw — Fork Change Log

This fork restyles [Aniyomi](https://github.com/aniyomiorg/aniyomi) with an iOS-inspired
design and a Home feed, while deliberately avoiding changes to data pipelines
(sources, extensions, sync, backup format, player engine).

**Imported from upstream:** Aniyomi `main` @ `9741444` ("feat: Add support for extensions-lib v17"),
fetched with `--depth=50` (shallow). See "Syncing with upstream" below.

---

## Design direction

Chosen from design mockups in [`design/`](design/) (AI-generated references, not pixel specs):
clean light surfaces, iOS system palette, big rounded corners, left navigation rail, no bottom bar.

## What was changed

| Change | Files | Notes |
|---|---|---|
| **Left side nav rail always on** (no bottom bar) | `app/src/main/java/eu/kanade/tachiyomi/ui/home/HomeScreen.kt` | The rail already existed for tablets (`isTabletUi()`); the gate was removed and the bottom bar deleted. `HomeScreen.showBottomNav()` kept as a no-op so player/reader calls don't break. |
| **New "Nw" theme** (iOS palette) | `presentation/theme/colorscheme/NwColorScheme.kt`, `domain/ui/model/AppTheme.kt`, `presentation/theme/TachiyomiTheme.kt`, `i18n-aniyomi/.../base/strings.xml` | Light: #F2F2F7 background, #007AFF blue. Dark: true black + #0A84FF. Registered as `AppTheme.NW` and set as the default in `UiPreferences.appTheme()`. |
| **iOS-style corner radii app-wide** | `presentation/theme/TachiyomiTheme.kt` | `NwShapes`: 10/14/16/20/28dp. Affects every Material component. |
| **Home tab (new)** | `ui/feed/FeedTab.kt`, `ui/feed/FeedScreenModel.kt`, `presentation/feed/FeedScreen.kt`, `domain/ui/model/NavStyle.kt`, `domain/ui/model/StartScreen.kt` | "Continue Watching" (from history) + "New Episodes" (from updates, last 30 days) horizontal cards. Read-only: reuses `GetAnimeHistory` / `GetAnimeUpdates`, creates no new data. Default start screen for fresh installs. |
| **App renamed to "Nw"** | `i18n/.../base/strings.xml` (`app_name`) | |
| **Own app identity** | `app/build.gradle.kts` | `applicationId = io.github.fahad0302042.nw` (installs alongside the real Aniyomi), `versionCode = getCommitCount()` (auto-bumps), `versionName = 1.0.0`. |
| **New logo** | `res/drawable/ic_launcher_background.xml`, `res/drawable/ic_launcher_foreground.xml`, `res/mipmap/ic_launcher.xml`, `res/mipmap/ic_launcher_round.xml` | Blue gradient + white play glyph. Foreground doubles as the themed/monochrome icon. |
| **Stable release signing** | `app/build.gradle.kts`, `keystore/` | See "Signing" below. |
| **Fork CI** | `.github/workflows/build.yml` | Builds a signed release APK on every push. Upstream's `build_push.yml` / `build_pull_request.yml` and `FUNDING.yml` were removed. |

## Signing (important)

Release builds are signed with `keystore/nw-release.jks` (PKCS12), read via
`keystore/keystore.properties`. Both are committed to the repo so CI signs
automatically with **zero setup** — this is what lets you install a new build
over the old one without uninstalling.

- **Keep a backup of `keystore/` somewhere safe** (download it once).
  Lose it = you can never update your installed app, only reinstall fresh.
- Because the repo is public, **anyone can sign an APK that Android will treat
  as an update to your app**. For a personal sideloaded app this is low risk
  (you only ever install builds from your own Actions), but do not ask other
  people to trust-install your builds.
- To rotate the key: generate a new PKCS12 (`openssl req -x509 ...` +
  `openssl pkcs12 -export ...`), replace both files, and accept that users
  must uninstall/reinstall once.

## Building (no PC needed)

1. Push any commit to the repo (GitHub web editor works on a phone).
2. The **Build Nw APK** workflow runs (~15–25 min).
3. Download the artifact `Nw-APK-<sha>` from the Actions tab (GitHub app/browser).
4. Install `Nw-arm64-v8a.apk` on a modern phone (or `Nw-universal.apk` for anything).

First build of this fork has never been compiled locally — if it fails, read the
error in the Actions log; it will point at the file to fix.

## Syncing with upstream

The branch history is a shallow (depth 50) import of upstream `main`, so recent
commits share a merge base:

```bash
git remote add aniyomi https://github.com/aniyomiorg/aniyomi.git   # once
git fetch aniyomi main
git merge aniyomi/main
# resolve conflicts — expect them in HomeScreen.kt, NavStyle.kt, UiPreferences.kt,
# app/build.gradle.kts (the files above); everything else should merge clean
```

If git complains about missing history, deepen first:
`git fetch --deepen=100 aniyomi main`.

Your FORK_CHANGES.md is the map: if a conflict touches a file listed above,
re-apply the intent (rail always on, NW default, FeedTab in list, own applicationId).

## Rotating the design

- **Colors:** `NwColorScheme.kt` — the two schemes are plain hex lists.
- **Corners:** `NwShapes` in `TachiyomiTheme.kt`.
- **Icon:** the two vector drawables under `res/drawable/`.
- **Name:** `app_name` in `i18n/.../base/strings.xml`.

## Not changed (on purpose)

Sources/extensions handling, trackers, backup format, player engine internals,
reader internals. Keep it that way and upstream merges stay cheap.
