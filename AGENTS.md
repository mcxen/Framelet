# Framelet Agent Guide

Read [ARCHITECTURE.md](ARCHITECTURE.md) before making cross-feature changes. It
contains the runtime data flows, state ownership, and module map.

## Fast navigation

| Need to change | Start here |
| --- | --- |
| Editor state, media loading, segment rules, crop, export UI state | `Sources/Framelet/Features/Editor/EditorStore.swift` |
| Player controls and crop overlay | `Features/Editor/Player/` |
| Timeline interaction and segment drawing | `Features/Editor/Timeline/` |
| Media, segment, and export panels | `Features/Editor/Inspector/` |
| FFmpeg command generation and progress | `MediaCore/FFmpeg/FFmpegRunner.swift` |
| FFmpeg process lifecycle / output draining | `MediaCore/FFmpeg/ProcessRunner.swift` |
| Persistent project format and crop/export settings | `Project/EditingProject.swift` |
| Shared services and app entry points | `App/AppServices.swift`, `App/FrameletApp.swift` |
| Update checks, background installation, and releases | `App/UpdateService.swift`, `Sources/FrameletUpdater/main.swift`, `.github/workflows/release.yml` |

## Invariants to preserve

- `EditorStore` is `@MainActor` and owns editor state. Views call store actions;
  do not duplicate mutation or validation in SwiftUI views.
- A new segment is an independent mark operation: successful creation clears
  `inPoint` and `outPoint`, selects the new segment, and keeps the playhead.
  Overlapping segments are valid; ranges equal within one frame are duplicates
  and must be rejected. Route boundary edits through `updateSegment` so the
  same duplicate rule applies.
- Segment names are monotonic `Segment N` labels. Do not re-use a lower label
  after deleting a segment.
- The project persists `EditingProject` as `.frameletproject`; keep Codable
  defaults backward-compatible when adding fields.
- All displayed edit times are relative to the media timeline. Keep
  `mediaStartTime` / `previewStartTime` conversions in `EditorStore` intact.
- Preview preparation must not await `AVPlayer.preroll(atRate:)`: some playable
  files never complete that callback. Seeking plus pausing is the supported
  paused-preview path.
- Crop coordinates and dimensions must be in bounds and even before FFmpeg is
  invoked. Use `setCropRectangle` and `CropSettings.rectangle`, not raw UI
  bindings.
- Export progress comes from FFmpeg `-progress` output. Preserve weighted
  segment progress, source-timestamp normalization, and actual concat progress;
  do not reintroduce timer-based or fixed-percentage estimates.

## Working conventions

- Use `apply_patch` for tracked-file edits. Preserve unrelated dirty changes.
- Localize new user-visible SwiftUI strings in both `Resources/en.lproj` and
  `Resources/zh-Hans.lproj`.
- Keep FFmpeg invocation code in `MediaCore`; UI/store code consumes
  `ExportEvent` rather than parsing process output.
- Add focused XCTest coverage in `Tests/FrameletTests` for state-machine or
  parser changes. Prefer direct `EditorStore` tests for editing rules.

## Release and updater workflow

- Push a semantic version tag such as `v0.2.0` to trigger
  `.github/workflows/release.yml`. The workflow builds the SwiftPM products for
  Apple Silicon, assembles `Framelet.app`, includes `FrameletUpdater`, writes
  the tag-derived `CFBundleShortVersionString`, signs the bundle, and publishes
  a GitHub Release.
- Preserve the unversioned release asset name exactly as
  `Framelet-macOS-arm64.zip`. The workflow may also publish a versioned archive,
  but the fixed name is the stable endpoint used by the in-app updater:
  `https://github.com/mcxen/Framelet/releases/latest/download/Framelet-macOS-arm64.zip`.
- Update checks must not use the GitHub REST API. Shared proxy exit addresses
  easily exhaust its anonymous rate limit. `UpdateService` follows the normal
  `https://github.com/mcxen/Framelet/releases/latest` redirect and extracts the
  version from the resulting `/releases/tag/vX.Y.Z` URL.
- Installation is owned by `FrameletUpdater`: the app launches the helper with
  its PID, the fixed HTTPS download URL, and the installed app path, then exits.
  The helper downloads and extracts the archive, verifies the expected
  `Framelet.app` executable, replaces the existing bundle with rollback
  protection, and reopens Framelet. On failure it must reopen the existing app.
- Keep the helper's download host/path allowlist and application-path checks.
  Do not accept an arbitrary update URL or replace an unrelated `.app` bundle.
- Before tagging a release, run the verification commands below and confirm
  that the workflow still uploads both the versioned archive and the fixed-name
  archive. The current release is ad-hoc signed and not notarized; do not claim
  Developer ID signing or notarization unless the workflow actually performs
  them.

## Verification

```bash
swift test
./script/build_and_run.sh --verify
git diff --check
```

The runner builds SwiftPM, stages `dist/Framelet.app`, and starts the fresh
macOS app. Do not launch the raw SwiftPM GUI executable for normal validation.
