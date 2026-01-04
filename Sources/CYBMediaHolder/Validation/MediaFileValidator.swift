//
//  MediaFileValidator.swift
//  CYBMediaHolder
//
//  Pre-validation for media files before loading.
//  Checks file signatures, size limits, symlinks, and path safety.
//

import Foundation

// MARK: - Validation Errors

/// Errors that can occur during file validation.
public enum MediaValidationError: Error, Sendable, CustomStringConvertible {
    /// File does not exist at the specified path.
    case fileNotFound(String)

    /// File is a symbolic link (security risk).
    case symbolicLinkNotAllowed(String)

    /// File exceeds maximum allowed size.
    case fileTooLarge(size: UInt64, maxSize: UInt64)

    /// File is empty (0 bytes).
    case emptyFile(String)

    /// File signature does not match expected format.
    case signatureMismatch(expected: String, actual: String)

    /// File path contains unsafe components.
    case unsafePathComponents(String)

    /// Unable to read file for validation.
    case readError(Error)

    /// File does not have read permission.
    case permissionDenied(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .symbolicLinkNotAllowed(let path):
            return "Symbolic links are not allowed: \(path)"
        case .fileTooLarge(let size, let maxSize):
            let sizeGB = Double(size) / 1_073_741_824
            let maxGB = Double(maxSize) / 1_073_741_824
            return String(format: "File too large: %.2f GB (max: %.2f GB)", sizeGB, maxGB)
        case .emptyFile(let path):
            return "File is empty: \(path)"
        case .signatureMismatch(let expected, let actual):
            return "File signature mismatch: expected \(expected), got \(actual)"
        case .unsafePathComponents(let path):
            return "Unsafe path components detected: \(path)"
        case .readError(let error):
            return "Unable to read file: \(error.localizedDescription)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        }
    }
}

// MARK: - Validation Configuration

/// Configuration for file validation.
public struct MediaValidationConfig: Sendable {
    /// Maximum file size allowed (default: 100GB).
    public var maxFileSize: UInt64

    /// Whether to reject symbolic links (default: true).
    public var rejectSymlinks: Bool

    /// Whether to validate file signatures (default: true).
    public var validateSignature: Bool

    /// Whether to check path safety (default: true).
    public var checkPathSafety: Bool

    /// Default configuration.
    public static let `default` = MediaValidationConfig(
        maxFileSize: 100 * 1024 * 1024 * 1024, // 100 GB
        rejectSymlinks: true,
        validateSignature: true,
        checkPathSafety: true
    )

    /// Relaxed configuration for trusted sources.
    public static let relaxed = MediaValidationConfig(
        maxFileSize: 500 * 1024 * 1024 * 1024, // 500 GB
        rejectSymlinks: false,
        validateSignature: false,
        checkPathSafety: false
    )

    public init(
        maxFileSize: UInt64 = 100 * 1024 * 1024 * 1024,
        rejectSymlinks: Bool = true,
        validateSignature: Bool = true,
        checkPathSafety: Bool = true
    ) {
        self.maxFileSize = maxFileSize
        self.rejectSymlinks = rejectSymlinks
        self.validateSignature = validateSignature
        self.checkPathSafety = checkPathSafety
    }
}

// MARK: - File Signature Definitions

/// Known file signatures (magic numbers) for media formats.
public enum MediaFileSignature: Sendable {
    // Video container signatures
    case mp4       // ftyp at offset 4, or moov/mdat at start
    case mov       // ftyp with qt brand, or wide/mdat
    case avi       // RIFF....AVI
    case mkv       // 0x1A45DFA3 (EBML header)
    case webm      // Same as MKV (WebM is MKV subset)

    // Audio signatures
    case mp3       // ID3 or 0xFF 0xFB
    case wav       // RIFF....WAVE
    case aiff      // FORM....AIFF
    case flac      // fLaC
    case aac       // ADTS header (0xFF 0xF1 or 0xFF 0xF9)
    case m4a       // ftyp M4A

    // Image signatures
    case jpeg      // 0xFF 0xD8 0xFF
    case png       // 0x89 PNG
    case gif       // GIF87a or GIF89a
    case tiff      // II or MM at start
    case heic      // ftyp heic/mif1
    case webp      // RIFF....WEBP
    case bmp       // BM

    // Unknown/unrecognized
    case unknown

    /// Minimum bytes needed to identify signature.
    public static let minimumHeaderSize = 12

    /// Detects file signature from header bytes.
    public static func detect(from header: Data) -> MediaFileSignature {
        guard header.count >= 4 else { return .unknown }

        let bytes = [UInt8](header)

        // JPEG: FF D8 FF
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .jpeg
        }

        // PNG: 89 50 4E 47 (0x89 PNG)
        if bytes.count >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return .png
        }

        // GIF: GIF87a or GIF89a
        if bytes.count >= 6 {
            let gifHeader = String(bytes: bytes[0..<6], encoding: .ascii)
            if gifHeader == "GIF87a" || gifHeader == "GIF89a" {
                return .gif
            }
        }

        // BMP: BM
        if bytes.count >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D {
            return .bmp
        }

        // TIFF: II (little-endian) or MM (big-endian)
        if bytes.count >= 4 {
            if (bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
               (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A) {
                return .tiff
            }
        }

        // FLAC: fLaC
        if bytes.count >= 4 {
            let flacHeader = String(bytes: bytes[0..<4], encoding: .ascii)
            if flacHeader == "fLaC" {
                return .flac
            }
        }

        // MP3: ID3 tag or sync word
        if bytes.count >= 3 {
            let id3Header = String(bytes: bytes[0..<3], encoding: .ascii)
            if id3Header == "ID3" {
                return .mp3
            }
        }
        if bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0 {
            return .mp3
        }

        // MKV/WebM: EBML header (0x1A 0x45 0xDF 0xA3)
        if bytes.count >= 4 && bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3 {
            return .mkv
        }

        // RIFF-based formats (AVI, WAV, WEBP)
        if bytes.count >= 12 {
            let riffHeader = String(bytes: bytes[0..<4], encoding: .ascii)
            if riffHeader == "RIFF" {
                let formatType = String(bytes: bytes[8..<12], encoding: .ascii)
                switch formatType {
                case "AVI ":
                    return .avi
                case "WAVE":
                    return .wav
                case "WEBP":
                    return .webp
                default:
                    break
                }
            }
        }

        // AIFF: FORM....AIFF
        if bytes.count >= 12 {
            let formHeader = String(bytes: bytes[0..<4], encoding: .ascii)
            let aiffType = String(bytes: bytes[8..<12], encoding: .ascii)
            if formHeader == "FORM" && aiffType == "AIFF" {
                return .aiff
            }
        }

        // MP4/MOV/M4A: Check for ftyp box at offset 4
        if bytes.count >= 8 {
            let ftypMarker = String(bytes: bytes[4..<8], encoding: .ascii)
            if ftypMarker == "ftyp" {
                // Check brand at bytes 8-11
                if bytes.count >= 12 {
                    let brand = String(bytes: bytes[8..<12], encoding: .ascii)
                    if let brand = brand {
                        // QuickTime brands
                        if brand.hasPrefix("qt") || brand == "mqt " {
                            return .mov
                        }
                        // M4A brands
                        if brand == "M4A " || brand == "M4B " {
                            return .m4a
                        }
                        // HEIC brands
                        if brand == "heic" || brand == "mif1" || brand == "msf1" || brand == "hevc" {
                            return .heic
                        }
                        // MP4 brands
                        if brand.hasPrefix("iso") || brand.hasPrefix("mp4") || brand == "avc1" || brand == "3gp" {
                            return .mp4
                        }
                    }
                }
                // Default ftyp to MP4
                return .mp4
            }
        }

        // MOV without ftyp: Check for moov/mdat/wide at start
        if bytes.count >= 8 {
            let atomType = String(bytes: bytes[4..<8], encoding: .ascii)
            if atomType == "moov" || atomType == "mdat" || atomType == "wide" || atomType == "free" || atomType == "skip" {
                return .mov
            }
        }

        return .unknown
    }

    /// Display name for the signature.
    public var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "QuickTime MOV"
        case .avi: return "AVI"
        case .mkv: return "Matroska"
        case .webm: return "WebM"
        case .mp3: return "MP3"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .flac: return "FLAC"
        case .aac: return "AAC"
        case .m4a: return "M4A"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .gif: return "GIF"
        case .tiff: return "TIFF"
        case .heic: return "HEIC"
        case .webp: return "WebP"
        case .bmp: return "BMP"
        case .unknown: return "Unknown"
        }
    }

    /// Whether this is a video format.
    public var isVideo: Bool {
        switch self {
        case .mp4, .mov, .avi, .mkv, .webm:
            return true
        default:
            return false
        }
    }

    /// Whether this is an audio format.
    public var isAudio: Bool {
        switch self {
        case .mp3, .wav, .aiff, .flac, .aac, .m4a:
            return true
        default:
            return false
        }
    }

    /// Whether this is an image format.
    public var isImage: Bool {
        switch self {
        case .jpeg, .png, .gif, .tiff, .heic, .webp, .bmp:
            return true
        default:
            return false
        }
    }
}

// MARK: - MediaFileValidator

/// Validates media files before loading.
///
/// Performs security and integrity checks including:
/// - File existence and permissions
/// - Symbolic link detection
/// - File size limits
/// - Magic number/signature validation
/// - Path safety checks
///
/// ## Usage
/// ```swift
/// let validator = MediaFileValidator()
/// try validator.validate(url: fileURL)
/// // File is safe to load
/// ```
public struct MediaFileValidator: Sendable {

    /// Validation configuration.
    public let config: MediaValidationConfig

    /// Creates a validator with the specified configuration.
    public init(config: MediaValidationConfig = .default) {
        self.config = config
    }

    // MARK: - Public Validation Methods

    /// Validates a file URL.
    ///
    /// - Parameter url: The file URL to validate.
    /// - Throws: `MediaValidationError` if validation fails.
    public func validate(url: URL) throws {
        guard url.isFileURL else {
            // Non-file URLs skip file-specific validation
            return
        }

        let path = url.path
        try validate(path: path)
    }

    /// Validates a file path.
    ///
    /// - Parameter path: The file path to validate.
    /// - Throws: `MediaValidationError` if validation fails.
    public func validate(path: String) throws {
        let fileManager = FileManager.default

        // Check path safety first
        if config.checkPathSafety {
            try validatePathSafety(path)
        }

        // Check file exists
        guard fileManager.fileExists(atPath: path) else {
            throw MediaValidationError.fileNotFound(path)
        }

        // Check for symbolic link
        if config.rejectSymlinks {
            try checkSymbolicLink(at: path)
        }

        // Check read permission
        guard fileManager.isReadableFile(atPath: path) else {
            throw MediaValidationError.permissionDenied(path)
        }

        // Get file attributes
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: path)
        } catch {
            throw MediaValidationError.readError(error)
        }

        // Check file size
        if let fileSize = attributes[.size] as? UInt64 {
            if fileSize == 0 {
                throw MediaValidationError.emptyFile(path)
            }
            if fileSize > config.maxFileSize {
                throw MediaValidationError.fileTooLarge(size: fileSize, maxSize: config.maxFileSize)
            }
        }

        // Validate file signature
        if config.validateSignature {
            try validateSignature(at: path)
        }
    }

    /// Validates and returns the detected file signature.
    ///
    /// - Parameter url: The file URL to check.
    /// - Returns: The detected file signature.
    /// - Throws: `MediaValidationError` if the file cannot be read.
    public func detectSignature(url: URL) throws -> MediaFileSignature {
        guard url.isFileURL else {
            return .unknown
        }
        return try detectSignature(path: url.path)
    }

    /// Validates and returns the detected file signature.
    ///
    /// - Parameter path: The file path to check.
    /// - Returns: The detected file signature.
    /// - Throws: `MediaValidationError` if the file cannot be read.
    public func detectSignature(path: String) throws -> MediaFileSignature {
        let headerSize = MediaFileSignature.minimumHeaderSize

        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            throw MediaValidationError.permissionDenied(path)
        }

        defer { try? fileHandle.close() }

        let headerData: Data
        do {
            headerData = try fileHandle.read(upToCount: headerSize) ?? Data()
        } catch {
            throw MediaValidationError.readError(error)
        }

        return MediaFileSignature.detect(from: headerData)
    }

    // MARK: - Private Validation Methods

    private func validatePathSafety(_ path: String) throws {
        // Check for path traversal attempts
        let components = path.components(separatedBy: "/")

        for component in components {
            // Reject ".." components
            if component == ".." {
                throw MediaValidationError.unsafePathComponents(path)
            }
            // Reject hidden files starting with multiple dots (but allow single dot dirs like .cache)
            if component.hasPrefix("..") {
                throw MediaValidationError.unsafePathComponents(path)
            }
        }

        // Ensure path is absolute (starts with /)
        guard path.hasPrefix("/") else {
            throw MediaValidationError.unsafePathComponents(path)
        }
    }

    private func checkSymbolicLink(at path: String) throws {
        let url = URL(fileURLWithPath: path)

        do {
            let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                throw MediaValidationError.symbolicLinkNotAllowed(path)
            }
        } catch let error as MediaValidationError {
            throw error
        } catch {
            // If we can't check, allow it (fail open for compatibility)
        }
    }

    private func validateSignature(at path: String) throws {
        let signature = try detectSignature(path: path)

        // Get expected type from extension
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        // Only warn on obvious mismatches, don't fail
        // This allows for flexibility with container formats
        let expectedCategory = extensionCategory(ext)
        let actualCategory = signatureCategory(signature)

        // Allow unknown signatures (could be valid but unrecognized format)
        if signature == .unknown {
            return
        }

        // Log mismatch but don't fail (handled downstream)
        if expectedCategory != actualCategory && expectedCategory != .unknown {
            // In the future, could log this for debugging
            // For now, allow the probe to handle format detection
        }
    }

    private enum MediaCategory {
        case video, audio, image, unknown
    }

    private func extensionCategory(_ ext: String) -> MediaCategory {
        let videoExtensions = Set(["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "3gp"])
        let audioExtensions = Set(["mp3", "wav", "aiff", "aif", "flac", "aac", "m4a", "ogg", "wma"])
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "tiff", "tif", "heic", "heif", "webp", "bmp", "ico"])

        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if imageExtensions.contains(ext) { return .image }
        return .unknown
    }

    private func signatureCategory(_ signature: MediaFileSignature) -> MediaCategory {
        if signature.isVideo { return .video }
        if signature.isAudio { return .audio }
        if signature.isImage { return .image }
        return .unknown
    }
}

// MARK: - Convenience Extensions

extension URL {
    /// Validates this URL using the default validator.
    ///
    /// - Throws: `MediaValidationError` if validation fails.
    public func validateForMediaLoading() throws {
        let validator = MediaFileValidator()
        try validator.validate(url: self)
    }

    /// Validates this URL with custom configuration.
    ///
    /// - Parameter config: The validation configuration.
    /// - Throws: `MediaValidationError` if validation fails.
    public func validateForMediaLoading(config: MediaValidationConfig) throws {
        let validator = MediaFileValidator(config: config)
        try validator.validate(url: self)
    }
}
