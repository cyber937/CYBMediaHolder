//
//  ColorInfo.swift
//  CYBMediaHolder
//
//  Color space and HDR metadata for video tracks.
//  Designed for accurate color pipeline handling.
//

import Foundation
import CoreMedia

/// Color primaries standard (ITU-R BT recommendations).
///
/// Defines the RGB primary chromaticities used to encode the video.
public enum ColorPrimaries: String, Codable, Sendable, CaseIterable {
    /// ITU-R BT.709 (sRGB, Rec.709) - Standard HD
    case bt709 = "bt709"

    /// ITU-R BT.2020 - Ultra HD / HDR
    case bt2020 = "bt2020"

    /// DCI-P3 - Digital Cinema
    case p3 = "p3"

    /// ITU-R BT.601 NTSC
    case bt601NTSC = "bt601_ntsc"

    /// ITU-R BT.601 PAL
    case bt601PAL = "bt601_pal"

    /// Unknown or unspecified
    case unknown = "unknown"

    /// Creates from CMFormatDescription color primaries.
    public init(from cfString: CFString?) {
        guard let cfString = cfString as String? else {
            self = .unknown
            return
        }
        switch cfString {
        case "ITU_R_709_2":
            self = .bt709
        case "ITU_R_2020":
            self = .bt2020
        case "P3_D65":
            self = .p3
        case "SMPTE_C":
            self = .bt601NTSC
        case "EBU_3213":
            self = .bt601PAL
        default:
            self = .unknown
        }
    }
}

/// Transfer function (gamma/EOTF).
///
/// Defines the electro-optical transfer function used.
public enum TransferFunction: String, Codable, Sendable, CaseIterable {
    /// ITU-R BT.709 transfer (gamma ~2.4)
    case bt709 = "bt709"

    /// sRGB transfer (gamma ~2.2)
    case sRGB = "srgb"

    /// Hybrid Log-Gamma (HLG) - HDR
    case hlg = "hlg"

    /// Perceptual Quantizer (PQ/ST.2084) - HDR
    case pq = "pq"

    /// Linear (gamma 1.0)
    case linear = "linear"

    /// Unknown or unspecified
    case unknown = "unknown"

    /// Creates from CMFormatDescription transfer function.
    public init(from cfString: CFString?) {
        guard let cfString = cfString as String? else {
            self = .unknown
            return
        }
        switch cfString {
        case "ITU_R_709_2":
            self = .bt709
        case "IEC_sRGB":
            self = .sRGB
        case "ITU_R_2100_HLG":
            self = .hlg
        case "SMPTE_ST_2084_PQ":
            self = .pq
        case "Linear":
            self = .linear
        default:
            self = .unknown
        }
    }

    /// Whether this transfer function is HDR.
    public var isHDR: Bool {
        switch self {
        case .hlg, .pq:
            return true
        default:
            return false
        }
    }
}

/// YCbCr matrix coefficients.
///
/// Defines the matrix used for RGB to YCbCr conversion.
public enum MatrixCoefficients: String, Codable, Sendable, CaseIterable {
    /// ITU-R BT.709
    case bt709 = "bt709"

    /// ITU-R BT.2020 non-constant luminance
    case bt2020NCL = "bt2020_ncl"

    /// ITU-R BT.2020 constant luminance
    case bt2020CL = "bt2020_cl"

    /// ITU-R BT.601 (NTSC)
    case bt601 = "bt601"

    /// Identity (RGB, no conversion)
    case identity = "identity"

    /// Unknown or unspecified
    case unknown = "unknown"

    /// Creates from CMFormatDescription matrix.
    public init(from cfString: CFString?) {
        guard let cfString = cfString as String? else {
            self = .unknown
            return
        }
        switch cfString {
        case "ITU_R_709_2":
            self = .bt709
        case "ITU_R_2020":
            self = .bt2020NCL
        case "SMPTE_170M_2004":
            self = .bt601
        default:
            self = .unknown
        }
    }
}

// Note: ChromaSubsampling is defined in CodecRegistry.swift as the single source of truth.
// It is imported here implicitly as it's in the same module.

/// Complete color information for a video track.
///
/// Encapsulates all color-related metadata needed for accurate rendering.
///
/// ## Design Notes
/// - All properties are optional to handle incomplete metadata
/// - `isHDR` computed property for quick HDR detection
/// - Designed for Metal/CoreImage color management integration
///
/// ## Future Extensions
/// - HDR mastering metadata (max/min luminance)
/// - Dolby Vision profile information
/// - ICC profile for non-standard color spaces
public struct ColorInfo: Codable, Sendable, Hashable {

    /// Color primaries (gamut).
    public let primaries: ColorPrimaries?

    /// Transfer function (gamma/EOTF).
    public let transferFunction: TransferFunction?

    /// YCbCr matrix coefficients.
    public let matrix: MatrixCoefficients?

    /// Whether full range (0-255) or video range (16-235).
    public let isFullRange: Bool?

    /// Bit depth per component (8, 10, 12, etc.).
    public let bitDepth: Int?

    /// Chroma subsampling format.
    public let chromaSubsampling: ChromaSubsampling?

    /// Creates a ColorInfo with all properties.
    public init(
        primaries: ColorPrimaries? = nil,
        transferFunction: TransferFunction? = nil,
        matrix: MatrixCoefficients? = nil,
        isFullRange: Bool? = nil,
        bitDepth: Int? = nil,
        chromaSubsampling: ChromaSubsampling? = nil
    ) {
        self.primaries = primaries
        self.transferFunction = transferFunction
        self.matrix = matrix
        self.isFullRange = isFullRange
        self.bitDepth = bitDepth
        self.chromaSubsampling = chromaSubsampling
    }

    /// Whether this represents HDR content.
    public var isHDR: Bool {
        transferFunction?.isHDR == true || primaries == .bt2020
    }

    /// Whether this is standard Rec.709 SDR content.
    public var isSDRRec709: Bool {
        primaries == .bt709 && transferFunction == .bt709
    }

    /// A default SDR Rec.709 color info.
    public static let sdrRec709 = ColorInfo(
        primaries: .bt709,
        transferFunction: .bt709,
        matrix: .bt709,
        isFullRange: false,
        bitDepth: 8,
        chromaSubsampling: .cs420
    )
}

// MARK: - CMFormatDescription Extension

extension ColorInfo {

    /// Creates ColorInfo from a CMFormatDescription.
    ///
    /// - Parameter formatDescription: The video format description.
    /// - Returns: ColorInfo with extracted color metadata.
    public init(from formatDescription: CMFormatDescription) {
        let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any] ?? [:]

        // Extract color primaries
        let primariesCF = extensions["CVColorPrimaries"] as? String
        self.primaries = ColorPrimaries(from: primariesCF as CFString?)

        // Extract transfer function
        let transferCF = extensions["CVTransferFunction"] as? String
        self.transferFunction = TransferFunction(from: transferCF as CFString?)

        // Extract matrix
        let matrixCF = extensions["CVYCbCrMatrix"] as? String
        self.matrix = MatrixCoefficients(from: matrixCF as CFString?)

        // Extract full range flag
        if let fullRange = extensions["CVFullRangeVideo"] as? Bool {
            self.isFullRange = fullRange
        } else {
            self.isFullRange = nil
        }

        // Extract bit depth from media subtype
        let subType = CMFormatDescriptionGetMediaSubType(formatDescription)
        self.bitDepth = ColorInfo.bitDepth(from: subType)

        // Extract chroma subsampling from media subtype
        self.chromaSubsampling = ColorInfo.chromaSubsampling(from: subType)
    }

    /// Extracts bit depth from codec FourCC using CodecRegistry.
    ///
    /// Falls back to 8-bit if codec is unknown.
    private static func bitDepth(from fourCC: FourCharCode) -> Int? {
        let fourCCString = fourCCToString(fourCC)
        if let characteristics = CodecRegistry.characteristics(for: fourCCString) {
            return characteristics.bitDepth
        }
        // Default to 8-bit for unknown codecs
        return 8
    }

    /// Extracts chroma subsampling from codec FourCC using CodecRegistry.
    ///
    /// Falls back to 4:2:0 if codec is unknown (most common consumer format).
    private static func chromaSubsampling(from fourCC: FourCharCode) -> ChromaSubsampling? {
        let fourCCString = fourCCToString(fourCC)
        if let characteristics = CodecRegistry.characteristics(for: fourCCString) {
            return characteristics.chromaSubsampling
        }
        // Default to 4:2:0 for unknown codecs (most consumer video)
        return .cs420
    }

    /// Converts FourCharCode to String for CodecRegistry lookup.
    private static func fourCCToString(_ fourCC: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar((fourCC >> 24) & 0xff),
            CChar((fourCC >> 16) & 0xff),
            CChar((fourCC >> 8) & 0xff),
            CChar(fourCC & 0xff),
            0
        ]
        return String(cString: bytes)
    }
}
