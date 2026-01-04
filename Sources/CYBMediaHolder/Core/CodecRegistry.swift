//
//  CodecRegistry.swift
//  CYBMediaHolder
//
//  Centralized codec information and characteristics.
//  Eliminates duplicate codec definitions across the codebase.
//

import Foundation

// MARK: - ChromaSubsampling

/// Chroma subsampling format indicating how color information is sampled.
///
/// Defined here as the single source of truth for chroma subsampling
/// across the codebase. Used by both `CodecCharacteristics` and `ColorInfo`.
///
/// ## Values
/// - `cs420`: 4:2:0 - Color sampled at 1/4 luma resolution (most common for H.264/HEVC)
/// - `cs422`: 4:2:2 - Color sampled at 1/2 luma horizontal resolution (ProRes 422)
/// - `cs444`: 4:4:4 - Full color resolution (ProRes 4444, uncompressed)
public enum ChromaSubsampling: String, Codable, Sendable, CaseIterable, Hashable {
    /// 4:2:0 subsampling - color at 1/4 resolution.
    case cs420 = "4:2:0"

    /// 4:2:2 subsampling - color at 1/2 horizontal resolution.
    case cs422 = "4:2:2"

    /// 4:4:4 subsampling - full color resolution.
    case cs444 = "4:4:4"

    /// Display-friendly description.
    public var displayName: String {
        rawValue
    }
}

// MARK: - CodecCharacteristics

/// Codec characteristics including color format and bit depth.
///
/// Used by `ColorInfo` for accurate codec-based metadata extraction.
public struct CodecCharacteristics: Sendable {
    /// Chroma subsampling format.
    public let chromaSubsampling: ChromaSubsampling

    /// Bit depth per component (8, 10, 12, etc.).
    public let bitDepth: Int

    /// Whether the codec supports alpha channel.
    public let hasAlpha: Bool

    public init(
        chromaSubsampling: ChromaSubsampling,
        bitDepth: Int,
        hasAlpha: Bool = false
    ) {
        self.chromaSubsampling = chromaSubsampling
        self.bitDepth = bitDepth
        self.hasAlpha = hasAlpha
    }
}

/// Centralized registry for codec information and characteristics.
///
/// This registry provides a single source of truth for codec-related
/// information, eliminating duplication across the codebase.
///
/// ## Usage
/// ```swift
/// if CodecRegistry.isIntraOnly("apch") {
///     // Handle ProRes as intra-frame codec
/// }
///
/// // Get codec characteristics
/// if let chars = CodecRegistry.characteristics(for: "ap4h") {
///     print("Chroma: \(chars.chromaSubsampling?.rawValue ?? "unknown")")
/// }
/// ```
public enum CodecRegistry {

    // MARK: - Intra-Only Codecs

    /// Codecs where every frame is a keyframe (I-frame only).
    /// These codecs support random access to any frame without decoding dependencies.
    public static let intraOnlyCodecs: Set<String> = [
        // Apple ProRes family
        "apch",  // ProRes 422 HQ
        "apcn",  // ProRes 422
        "apcs",  // ProRes 422 LT
        "apco",  // ProRes 422 Proxy
        "ap4h",  // ProRes 4444
        "ap4x",  // ProRes 4444 XQ
        "aprh",  // ProRes RAW HQ
        "aprn",  // ProRes RAW

        // Avid DNxHD/HR
        "AVdn",  // Avid DNxHD
        "AVdh",  // Avid DNxHR

        // Other professional codecs
        "cfhd",  // CineForm
        "r210",  // 10-bit RGB
        "v210",  // 10-bit 4:2:2
        "v410",  // 10-bit 4:4:4
        "r10k",  // AJA KONA 10-bit RGB
        "v308",  // 8-bit 4:4:4
        "v408",  // 8-bit 4:4:4:4

        // Motion JPEG variants
        "jpeg",  // Motion JPEG
        "mjpg",  // Motion JPEG
        "mjpa",  // Motion JPEG A
        "mjpb",  // Motion JPEG B
        "dmb1",  // Motion JPEG OpenDML

        // Image sequence codes
        "png ",  // PNG
        "tiff",  // TIFF
        "tif ",  // TIFF variant
        "bmp ",  // BMP
        "tga ",  // TGA
        "dpx ",  // DPX
        "exr ",  // OpenEXR
    ]

    /// Checks if a codec is intra-only (every frame is a keyframe).
    ///
    /// - Parameter fourCC: The codec's FourCC identifier.
    /// - Returns: True if the codec is intra-only.
    public static func isIntraOnly(_ fourCC: String) -> Bool {
        intraOnlyCodecs.contains(fourCC.lowercased()) ||
        intraOnlyCodecs.contains(fourCC)
    }

    // MARK: - Codec Display Names

    /// Human-readable names for common codecs.
    public static let codecDisplayNames: [String: String] = [
        // Apple ProRes
        "ap4h": "Apple ProRes 4444",
        "ap4x": "Apple ProRes 4444 XQ",
        "apch": "Apple ProRes 422 HQ",
        "apcn": "Apple ProRes 422",
        "apcs": "Apple ProRes 422 LT",
        "apco": "Apple ProRes 422 Proxy",
        "aprh": "Apple ProRes RAW HQ",
        "aprn": "Apple ProRes RAW",

        // H.264/H.265
        "avc1": "H.264",
        "avc3": "H.264",
        "hvc1": "H.265/HEVC",
        "hev1": "H.265/HEVC",

        // AV1
        "av01": "AV1",

        // VP8/VP9
        "vp08": "VP8",
        "vp09": "VP9",

        // Avid
        "AVdn": "Avid DNxHD",
        "AVdh": "Avid DNxHR",

        // Audio codecs
        "mp4a": "AAC",
        "ac-3": "Dolby Digital",
        "ec-3": "Dolby Digital Plus",
        "alac": "Apple Lossless",
        "lpcm": "Linear PCM",
        "sowt": "Linear PCM (Little Endian)",
        "twos": "Linear PCM (Big Endian)",
        ".mp3": "MP3",
    ]

    /// Gets a human-readable display name for a codec.
    ///
    /// - Parameter fourCC: The codec's FourCC identifier.
    /// - Returns: Human-readable name, or the FourCC if unknown.
    public static func displayName(for fourCC: String) -> String {
        codecDisplayNames[fourCC] ?? fourCC
    }

    // MARK: - Codec Characteristics

    /// Professional editing-friendly codecs.
    /// These codecs are optimized for editing workflows (low decode latency, consistent frame sizes).
    public static let editFriendlyCodecs: Set<String> = [
        "apch", "apcn", "apcs", "apco", "ap4h", "ap4x", "aprh", "aprn",
        "AVdn", "AVdh", "cfhd"
    ]

    /// Codecs that support efficient reverse playback.
    /// Intra-only codecs naturally support reverse playback.
    public static func supportsReversePlayback(_ fourCC: String) -> Bool {
        isIntraOnly(fourCC)
    }

    /// Checks if a codec is suitable for professional editing.
    ///
    /// - Parameter fourCC: The codec's FourCC identifier.
    /// - Returns: True if the codec is editing-friendly.
    public static func isEditFriendly(_ fourCC: String) -> Bool {
        editFriendlyCodecs.contains(fourCC.lowercased()) ||
        editFriendlyCodecs.contains(fourCC)
    }

    // MARK: - Apple ProRes Helpers

    /// Apple ProRes codec variants.
    public static let proResCodecs: Set<String> = [
        "apch", "apcn", "apcs", "apco", "ap4h", "ap4x", "aprh", "aprn"
    ]

    /// Checks if a codec is Apple ProRes.
    ///
    /// - Parameter fourCC: The codec's FourCC identifier.
    /// - Returns: True if the codec is ProRes.
    public static func isProRes(_ fourCC: String) -> Bool {
        proResCodecs.contains(fourCC)
    }

    // MARK: - Codec Characteristics Lookup

    /// Codec characteristics by FourCC.
    ///
    /// Contains chroma subsampling, bit depth, and alpha information
    /// for accurate color pipeline configuration.
    public static let codecCharacteristics: [String: CodecCharacteristics] = [
        // Apple ProRes 422 family (4:2:2, 10-bit)
        "apch": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 10),
        "apcn": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 10),
        "apcs": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 10),
        "apco": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 10),

        // Apple ProRes 4444 family (4:4:4, 12-bit, with alpha)
        "ap4h": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 12, hasAlpha: true),
        "ap4x": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 12, hasAlpha: true),

        // Apple ProRes RAW (Bayer, treated as 4:4:4 for pipeline purposes)
        "aprh": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 12),
        "aprn": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 12),

        // H.264/AVC variants (typically 4:2:0, 8-bit)
        "avc1": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 8),
        "avc3": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 8),

        // H.265/HEVC variants
        "hvc1": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 8),
        "hev1": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 8),

        // 10-bit HEVC (common for HDR)
        "dvh1": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 10),

        // AV1
        "av01": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 10),

        // VP8/VP9
        "vp08": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 8),
        "vp09": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 8),

        // Avid DNxHD/HR (4:2:2, 8-bit or 10-bit depending on profile)
        "AVdn": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 8),
        "AVdh": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 10),

        // CineForm (4:2:2, 10-bit)
        "cfhd": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 10),

        // Uncompressed formats
        "r210": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 10),
        "v210": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 10),
        "v410": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 10),
        "r10k": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 10),
        "v308": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 8),
        "v408": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 8, hasAlpha: true),

        // Motion JPEG (4:2:2 or 4:2:0, 8-bit)
        "jpeg": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 8),
        "mjpg": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 8),
        "mjpa": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 8),
        "mjpb": CodecCharacteristics(chromaSubsampling: .cs422, bitDepth: 8),
        "dmb1": CodecCharacteristics(chromaSubsampling: .cs420, bitDepth: 8),

        // Image sequence formats (4:4:4)
        "png ": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 8, hasAlpha: true),
        "tiff": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 16),
        "tif ": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 16),
        "bmp ": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 8),
        "tga ": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 8, hasAlpha: true),
        "dpx ": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 10),
        "exr ": CodecCharacteristics(chromaSubsampling: .cs444, bitDepth: 16, hasAlpha: true),
    ]

    /// Gets codec characteristics for a FourCC.
    ///
    /// - Parameter fourCC: The codec's FourCC identifier.
    /// - Returns: Codec characteristics if known, nil otherwise.
    public static func characteristics(for fourCC: String) -> CodecCharacteristics? {
        let trimmed = fourCC.trimmingCharacters(in: .whitespaces)
        return codecCharacteristics[trimmed] ?? codecCharacteristics[fourCC]
    }
}
