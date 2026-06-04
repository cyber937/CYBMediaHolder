# Upgrading to v1.0.0

> ⚠️ **注意 / Caveat**
> 新しいバージョン（**v1.0.0**）を使用する場合は、これらのことに注意して使用してください。
> When adopting **v1.0.0**, review the notes below before upgrading. Some media *facts* change value, and identity/cache behavior changes.

_Status: these notes apply to the **v1.0.0** release (the correctness fixes for the AVFoundation bridge and the identity/cache layer). They do not describe v0.1.x behavior._

v1.0.0 corrects a set of long-standing defects: color/HDR and timecode metadata that were silently never extracted, and an identity/cache layer that could not persist across launches. The **public API stays source-compatible** — your code keeps compiling — but several values that were previously dead or incorrect now become correct, and identity/cache semantics change. Treat this as a **re-verify + one-time migration**, not a rewrite.

## TL;DR

| Category | What changes | Action required |
|---|---|---|
| Behavioral (color/HDR, timecode, DAR/VFR, capabilities) | Values become correct | Re-verify branches that read them. No code change. |
| Identity (`MediaID`) | Value + equality semantics change | If you persist `MediaID`, migrate or re-index. |
| Cache (L2 on disk) | Filename scheme becomes stable | Accept a one-time cold cache after upgrade. |
| Validation (signature) | Mismatch can now be rejected | Opt-in only — enable deliberately and check for false positives. |

## 1. Behavioral changes — re-verify (no code change)

These now return *correct* values where they previously returned dead/placeholder values. If your app branches on them, the branch outcome changes.

- **Color / HDR** — `holder.isHDR`, `ColorInfo.primaries`, `.transferFunction`, `.matrix`, `.isFullRange` were previously always `false` / `.unknown` for AVFoundation-probed media. They now reflect real values (BT.709 / BT.2020 / HLG / PQ / P3, full-range). HDR-dependent UI (badges, tone-mapping) will start firing for genuine HDR content.
- **Timecode** — `getTimecodeRate()` / `getTimecodeDropFrame()` / `getTimecodeStart()` previously always reported `30.0` / `false` / a 30 fps–derived string. They now reflect the real frame rate (e.g. 23.976, 25, 29.97), the drop-frame flag, and a correctly computed start timecode. Anything that assumed "rate is always 30" must be re-checked.
- **Display aspect ratio / VFR** — `VideoTrackDescriptor.displayAspectRatio` now reflects the real DAR (or `nil`) instead of a raw pixel ratio, and `isVFR` no longer false-positives on simply edited/trimmed constant-frame-rate clips.
- **Capabilities** — when a keyframe index already exists, `.keyframeIndexGeneratable` is no longer also advertised. UI that toggles a "Generate index" affordance off `caps.contains(.keyframeIndexGeneratable)` now behaves correctly.

➡️ **What to do:** QA the screens that read color/HDR, timecode, DAR, VFR, and capability flags. No source changes are required.

## 2. Identity migration — `MediaID`

Before v1.0.0, `MediaID` was a fresh random UUID per `create(...)` call (content hashing was never performed). v1.0.0 makes identity content-stable, which means:

- **The `MediaID` value changes.** If you persist `MediaID` (library database keys, bookmark associations, `Codable` snapshots, SwiftUI `Identifiable` storage), previously stored IDs will not match newly computed ones.
- **Equality semantics change.** Two holders created from the same file are now equal (`==`) and hash equally, instead of being distinct. If you intentionally relied on per-instance identity (e.g. the same asset appearing as two separate entries), revisit that assumption.

➡️ **What to do:**
1. Inventory whether your app persists `MediaID` anywhere.
2. If yes, run a one-time migration (old ID → new content-stable ID) **or** re-index the affected store on first launch after upgrade.
3. If you do not persist `MediaID`, no action is needed.

## 3. Cache cold start — L2 (disk)

The on-disk cache filename scheme changes to a stable key. It previously derived from `MediaID.hashValue`, which is randomized per process and therefore could not survive a relaunch. After upgrading:

- **Expect a one-time cold L2 cache.** Analysis (waveform / peak / keyframe) regenerates once, then persists correctly across sessions going forward.
- Old cache files written by v0.1.x are orphaned; clear the cache directory on upgrade if you want to reclaim the space immediately.

➡️ **What to do:** Accept the first-run regeneration; optionally purge the legacy cache directory during your upgrade step.

## 4. Signature enforcement — opt-in

v1.0.0 can reject files whose magic-number signature does not match their extension. Because a signature database can produce false positives, this is **opt-in** via `MediaValidationConfig`:

- Leave it disabled to preserve current load behavior.
- Enable it deliberately, and verify your existing library does not surface false rejections before shipping.

➡️ **What to do:** Keep signature enforcement off by default; enable and test against a representative library before turning it on.

## Swift Package Manager pinning

If your app depends on this package with `from: "0.1.0"`, SPM treats `0.x` releases as `< 1.0.0`, so it will **not** auto-resolve to `1.0.0` — you opt in explicitly:

```swift
.package(url: "https://github.com/cyber937/CYBMediaHolder.git", from: "1.0.0")
```

Pin to the version you have validated, and upgrade on your own schedule.
