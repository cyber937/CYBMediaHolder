# Changelog

All notable changes to CYBMediaHolder are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-04

First stable release. Corrects several defects where media facts were silently
never extracted, and makes identity/cache behavior survive app launches.

> ⚠️ Upgrading from 0.1.x changes observed *values* and identity/cache semantics.
> The public API stays source-compatible, but review
> [doc/UPGRADING.md](doc/UPGRADING.md) before adopting (re-verify + one-time
> migration, not a rewrite).

### Fixed

- **Color / HDR metadata is now extracted.** `ColorInfo(from:)` was reading
  non-existent `CMFormatDescription` extension keys (`"CVColorPrimaries"`,
  `"CVTransferFunction"`, `"CVYCbCrMatrix"`, `"CVFullRangeVideo"`), so color
  primaries, transfer function, matrix, and full-range were always
  `.unknown`/`nil` and `isHDR` was always `false` for AVFoundation-probed video.
  It now reads the canonical `kCMFormatDescriptionExtension_*` keys. Also corrects
  the BT.601 matrix value to `"ITU_R_601_4"` (previously the non-existent
  `"SMPTE_170M_2004"`).
- **Timecode frame rate and drop-frame flag are now read** from the dedicated
  `CMTimeCodeFormatDescriptionGetFrameDuration` / `GetFrameQuanta` /
  `GetTimeCodeFlags` accessors instead of non-existent dictionary keys. tmcd
  tracks previously always reported 30 fps and non-drop-frame.
- **Drop-frame timecode conversion** now performs correct SMPTE renumbering for
  29.97 / 59.94 instead of only changing the separator; hours wrap at 24h.
- **Display aspect ratio** no longer divides by zero — it stores `nil` for
  degenerate track sizes instead of `NaN`/`inf`.
- **Disk (L2) cache now persists across launches.** Cache filenames were derived
  from `MediaID.hashValue`, which Swift seeds randomly per process; they now use
  the stable `MediaID` UUID, so cached analysis survives a relaunch and
  `removeAll(for:)` matches reliably.
- `WaveformData` now validates that `minSamples` and `maxSamples` have equal
  length at construction (prevents an out-of-bounds trap during rendering).
- A media item that already has a keyframe index no longer also advertises
  `.keyframeIndexGeneratable`.

### Changed

- **`MediaID` is now content-stable for local files.** Identity is derived from a
  fingerprint of the file (size + up to 64 KiB of head/tail), so two holders for
  the same file share one identity. Equality and hashing are now based on `uuid`
  alone; `contentHash`/`bookmarkHash` are informational.
  **Migration:** if you persist `MediaID`, migrate or re-index — see
  [doc/UPGRADING.md](doc/UPGRADING.md).

### Added

- `MediaValidationConfig.enforceSignatureMatching` (default `false`): opt-in
  rejection of files whose magic-number signature does not match their
  extension's media category, throwing `MediaValidationError.signatureMismatch`.
  Off by default to preserve existing load behavior.
- `MediaID.contentStableIdentity(forFileAt:)` for deriving content-stable
  identity from a local file.
- `doc/UPGRADING.md` migration guide and this changelog.
- Unit tests for drop-frame/non-drop-frame timecode conversion, content-stable
  `MediaID`, color/transfer/matrix CFString mapping, and signature enforcement.

### Notes

- The public API remains source-compatible with 0.1.x; the items above change
  observed *values* and identity/cache behavior, not type signatures. SPM users
  on `from: "0.1.0"` will **not** auto-resolve to `1.0.0` (it is `>= 1.0.0`); bump
  the requirement explicitly.

## [0.1.0]

- Initial release.
