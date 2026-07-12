# Framelet Architecture

Framelet is a SwiftPM macOS 14+ SwiftUI editor for marking media ranges and
exporting them through FFmpeg. The app runs one editor window and one
`EditorStore` at a time.

## Runtime shape

```text
FrameletApp
  └─ AppServices (shared concrete services)
       └─ EditorStore (@MainActor, editor source of truth)
            ├─ EditorView / PlayerPane / TimelinePane / InspectorView
            ├─ AVPlayer + AVPlayerView preview
            ├─ EditingProject (.frameletproject persistence model)
            └─ MediaCore actors/services (FFprobe, FFmpeg, thumbnails, waveform, proxy)
```

`FrameletApp` creates `AppServices` and its single `EditorStore`; child views
receive that same store explicitly. `AppCommands` posts notifications that
`EditorView` routes to store actions.

## Module map

| Area | Responsibility | Primary files |
| --- | --- | --- |
| `App/` | App lifecycle, commands, settings, service composition | `FrameletApp.swift`, `AppServices.swift`, `AppCommands.swift` |
| `Features/Editor/` | Editor state and SwiftUI composition | `EditorStore.swift`, `EditorView.swift` |
| `Features/Editor/Player/` | AVPlayer host, transport, crop interaction | `PlayerPane.swift`, `TransportBar.swift`, `PlayerViewRepresentable.swift` |
| `Features/Editor/Timeline/` | AppKit-backed timeline drawing and pointer gestures | `TimelinePane.swift`, `TimelineViewRepresentable.swift` |
| `Features/Editor/Inspector/` | Media, segment, and export panels | `MediaInspector.swift`, `SegmentInspector.swift`, `ExportInspector.swift` |
| `Project/` | Codable project, segment, crop, CSV persistence | `EditingProject.swift`, `ProjectStore.swift`, `SegmentCSV.swift` |
| `MediaCore/Probe` | FFprobe JSON to `MediaInfo` | `FFprobeService.swift`, `MediaProbeService.swift` |
| `MediaCore/Analysis` | Keyframes, thumbnails, waveform | `KeyframeService.swift`, `ThumbnailService.swift`, `WaveformService.swift` |
| `MediaCore/FFmpeg` | Tool lookup, process ownership, export commands/progress | `ToolResolver.swift`, `ProcessRunner.swift`, `FFmpegRunner.swift` |
| `MediaCore/Proxy` | Compatible preview proxy generation | `ProxyBuilder.swift` |
| `Infrastructure/` | Time formatting and sandbox/bookmark file access | `TimecodeFormatter.swift`, `FileAccessService.swift` |

## Core flows

### Open media and prepare preview

1. `EditorStore.openMedia` cancels prior analysis tasks and advances a media
   generation token.
2. `loadMedia` makes a persistent `MediaReference`, loads AVFoundation duration,
   probes metadata with FFprobe, then updates `mediaStartTime`, display duration,
   streams, and project defaults.
3. `preparePreview` replaces the `AVPlayerItem`, checks the asset is playable,
   seeks to the display time translated by `previewStartTime`, then pauses. Do
   not await AVPlayer preroll here.
4. Independent background tasks build keyframes, thumbnails, and waveform. Each
   checks the generation token before publishing results.

Display time is relative to the user-visible timeline. Source/proxy preview
time is translated through `previewStartTime`; FFmpeg source time adds
`mediaStartTime` through `ExportJob.sourceStartOffset`.

### Segments

`EditingProject.segments` is the ordered set used by the timeline and export.
The store owns all segment mutations:

1. `setInPoint` and `setOutPoint` mark the current display time.
2. `createSegmentFromMarks` validates ordering and delegates to `createSegment`.
3. A successful create appends a unique `Segment N`, selects it, clears both
   marks, and leaves playback time untouched.
4. Ranges that match another segment within `frameStepDuration` are duplicates;
   the existing segment is selected instead. Overlaps that are not equivalent
   are allowed.
5. Timeline drags and inspector boundary controls call `updateSegment`. It
   preserves a minimum duration, clamps to media duration, and applies the same
   duplicate rule. Reordering only changes export/list order.

`SegmentInspector` always lists all segments. Selecting a row seeks to its
start; the selected item exposes name, boundaries, enable state, color, and
keyframe diagnostics.

### Crop and preview

Crop interaction lives in `PlayerPane`; it only emits `CropRectangle` updates.
`EditorStore.setCropRectangle` normalizes all values to even, in-bounds pixel
coordinates. `CropSettings.rectangle` performs the final persisted-settings
validation before export. A crop switches video export from stream copy to the
configured H.264 encoder while other compatible streams are copied.

### Export and progress

1. `EditorStore.exportSeparateSegments` builds an immutable `ExportJob` from
   the project and starts consuming `FFmpegRunner.export` events.
2. `FFmpegRunner` exports enabled segments in project order. Separate output
   uses direct files; merged output uses temporary segments then the concat
   demuxer.
3. Every FFmpeg process uses `-progress pipe:1`; `FFmpegProgressParser` parses
   `out_time_*` and speed. Segment progress is duration-weighted. Stream-copy
   source timestamps are normalized before calculating a fraction.
4. Merged exports reserve the final 5% for concat and update that portion from
   concat's real progress output. `ExportInspector` displays phase, segment
   count, fraction, speed, and a wall-clock remaining estimate.

`ProcessRunner` must drain stdout and stderr concurrently to prevent a child
process pipe deadlock. Process output parsing stays in `MediaCore`, never in
the UI.

## State and concurrency

- `EditorStore` runs on the main actor; it owns UI-observable state.
- `FFmpegRunner` is an actor. `ProcessRunner` uses a locked continuation state
  because pipe reads and process termination arrive on separate queues.
- Media-analysis tasks are cancellable and generation-scoped. A stale task may
  finish but must not publish its result after a different media file opens.
- `CommandLog` is shared through `AppServices` so inspector diagnostics can
  show FFprobe, FFmpeg, waveform, proxy, and export commands.

## Persistence and compatibility

- Projects are JSON `.frameletproject` files managed by `ProjectStore`.
- `EditingProject.currentSchemaVersion` is currently `1`. Add new persisted
  fields with Codable defaults/`decodeIfPresent` so existing projects load.
- `FileAccessService` owns security-scoped bookmark creation and resolution.

## Tests and local verification

- `ExportPresetTests` covers editor/project state rules, including independent
  multiple-segment creation, duplicate rejection, overlap permission, and
  monotonic names.
- `ProcessRunnerTests` covers pipe draining, error reporting, and split FFmpeg
  progress parsing.
- `SegmentCSVTests` covers malformed and non-finite CSV timing input.

Run `swift test` after changes. For the packaged GUI app, use
`./script/build_and_run.sh --verify`; it builds and launches
`dist/Framelet.app`.
