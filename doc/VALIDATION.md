# File Validation

CYBMediaHolder includes a comprehensive file validation system to ensure security and integrity before loading media files.

## Overview

`MediaFileValidator` performs pre-loading checks including:

- File existence and permissions
- Symbolic link detection
- File size limits
- Magic number/signature validation
- Path safety checks

## Basic Usage

```swift
let validator = MediaFileValidator()
try validator.validate(url: fileURL)
// File is safe to load
```

Validation is automatically performed during `MediaHolder.create()`:

```swift
// Validation happens automatically
let holder = try await MediaHolder.create(from: fileURL)
```

## Configuration

### Default Configuration

```swift
let config = MediaValidationConfig.default
// maxFileSize: 100 GB
// rejectSymlinks: true
// validateSignature: true
// checkPathSafety: true
```

### Relaxed Configuration

For trusted sources:

```swift
let config = MediaValidationConfig.relaxed
// maxFileSize: 500 GB
// rejectSymlinks: false
// validateSignature: false
// checkPathSafety: false
```

### Custom Configuration

```swift
let config = MediaValidationConfig(
    maxFileSize: 50 * 1024 * 1024 * 1024,  // 50 GB
    rejectSymlinks: true,
    validateSignature: true,
    checkPathSafety: true
)

let holder = try await MediaHolder.create(
    from: fileURL,
    validationConfig: config
)
```

## Validation Checks

### Path Safety

Prevents path traversal attacks:

```swift
// Rejected paths:
"/Users/../etc/passwd"     // Contains ..
"relative/path/file.mp4"   // Not absolute
```

### Symbolic Links

Prevents symlink-based attacks (enabled by default):

```swift
// Rejected if pointing to symlink
/Users/media/video.mp4 -> /etc/sensitive
```

### File Size

Enforces maximum file size:

```swift
// Default: 100 GB max
// Configurable via maxFileSize
```

### File Signature

Validates magic numbers match file extension category:

| Format    | Signature                    |
| --------- | ---------------------------- |
| JPEG      | `FF D8 FF`                   |
| PNG       | `89 50 4E 47`                |
| MP4       | `ftyp` at offset 4           |
| MOV       | `ftyp qt` or `moov/mdat`     |
| MKV/WebM  | `1A 45 DF A3` (EBML)         |
| AVI       | `RIFF....AVI`                |
| MP3       | `ID3` or `FF FB`             |
| WAV       | `RIFF....WAVE`               |
| FLAC      | `fLaC`                       |

## Error Handling

```swift
do {
    try validator.validate(url: fileURL)
} catch MediaValidationError.fileNotFound(let path) {
    print("File not found: \(path)")

} catch MediaValidationError.symbolicLinkNotAllowed(let path) {
    print("Symlinks not allowed: \(path)")

} catch MediaValidationError.fileTooLarge(let size, let maxSize) {
    print("File \(size) bytes exceeds limit \(maxSize)")

} catch MediaValidationError.emptyFile(let path) {
    print("File is empty: \(path)")

} catch MediaValidationError.signatureMismatch(let expected, let actual) {
    print("Expected \(expected), got \(actual)")

} catch MediaValidationError.unsafePathComponents(let path) {
    print("Unsafe path: \(path)")

} catch MediaValidationError.permissionDenied(let path) {
    print("Cannot read: \(path)")

} catch MediaValidationError.readError(let error) {
    print("Read error: \(error)")
}
```

## Signature Detection

Detect file format from content:

```swift
let validator = MediaFileValidator()
let signature = try validator.detectSignature(url: fileURL)

switch signature {
case .mp4:
    print("MP4 video")
case .mov:
    print("QuickTime movie")
case .jpeg:
    print("JPEG image")
case .unknown:
    print("Unknown format")
default:
    print(signature.displayName)
}
```

### MediaFileSignature

```swift
public enum MediaFileSignature {
    // Video
    case mp4, mov, avi, mkv, webm

    // Audio
    case mp3, wav, aiff, flac, aac, m4a

    // Image
    case jpeg, png, gif, tiff, heic, webp, bmp

    case unknown

    var isVideo: Bool { ... }
    var isAudio: Bool { ... }
    var isImage: Bool { ... }
    var displayName: String { ... }
}
```

## URL Extension

Convenience methods on URL:

```swift
// With default config
try fileURL.validateForMediaLoading()

// With custom config
try fileURL.validateForMediaLoading(config: .relaxed)
```

## Security Considerations

### Why Reject Symlinks?

Symbolic links can point to sensitive files outside the expected directory:

```swift
// Attack scenario:
// video.mp4 -> /etc/passwd
// Application reads "video" but gets system file

// Protection:
config.rejectSymlinks = true
```

### Why Validate Signatures?

Prevents disguised files from being loaded:

```swift
// Attack scenario:
// malware.exe renamed to video.mp4
// Signature check reveals it's not actually MP4
```

### Why Check Path Safety?

Prevents directory traversal:

```swift
// Attack scenario:
// User provides: "../../../etc/passwd"
// Path safety rejects non-absolute and traversal paths
```

## Best Practices

1. **Use default config** for user-provided files
2. **Use relaxed config** only for trusted sources (your own app bundle, verified downloads)
3. **Handle all error types** to provide meaningful user feedback
4. **Log validation failures** for security monitoring
5. **Don't disable validation** just to make things work
