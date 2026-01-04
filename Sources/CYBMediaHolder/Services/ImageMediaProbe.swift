//
//  ImageMediaProbe.swift
//  CYBMediaHolder
//
//  Image-based implementation of MediaProbe.
//  Extracts media descriptors from image files using CoreGraphics/ImageIO.
//

import Foundation
import CoreMedia
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os.log

/// Logger for image probe operations.
private let logger = Logger(subsystem: "com.cyberseeds.CYBMediaHolder", category: "ImageProbe")

/// Image-based media probe implementation.
///
/// Uses ImageIO/CoreGraphics to extract image information including:
/// - Image dimensions
/// - Color space information
/// - File format/codec
/// - EXIF/metadata
///
/// ## Supported Formats
/// - JPEG (.jpg, .jpeg)
/// - PNG (.png)
/// - GIF (.gif)
/// - TIFF (.tiff, .tif)
/// - HEIC/HEIF (.heic, .heif)
/// - BMP (.bmp)
/// - WebP (.webp)
///
/// ## Limitations
/// - No video/audio track extraction (images only)
/// - Animation (GIF, APNG) treated as single frame
public struct ImageMediaProbe: MediaProbe, Sendable {

    public let identifier = "ImageIO"
    public let displayName = "ImageIO"

    public let supportedExtensions: Set<String> = [
        // Common image formats
        "jpg", "jpeg", "png", "gif", "tiff", "tif",
        // Modern formats
        "heic", "heif", "webp",
        // Other formats
        "bmp", "ico"
    ]

    public let supportedUTTypes: Set<String> = [
        "public.image",
        "public.jpeg",
        "public.png",
        "public.tiff",
        "com.compuserve.gif",
        "public.heic",
        "public.heif",
        "org.webmproject.webp"
    ]

    public init() {}

    // MARK: - Probing

    public func probe(locator: MediaLocator) async throws -> MediaDescriptor {
        // Resolve the locator to a URL
        let resolved: MediaLocator.ResolvedURL
        do {
            resolved = try await locator.resolve()
        } catch let error as MediaLocator.ResolutionError {
            throw MediaProbeError.locatorResolutionFailed(error)
        }

        defer {
            resolved.stopAccessing()
        }

        let url = resolved.url

        // Create image source
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MediaProbeError.unsupportedFormat("Failed to create image source")
        }

        // Get image count (for animated GIFs, etc.)
        let imageCount = CGImageSourceGetCount(imageSource)
        guard imageCount > 0 else {
            throw MediaProbeError.noTracksFound
        }

        // Get primary image properties
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            throw MediaProbeError.propertyLoadFailed(NSError(domain: "ImageProbe", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get image properties"]))
        }

        // Extract dimensions
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0

        guard width > 0 && height > 0 else {
            throw MediaProbeError.propertyLoadFailed(NSError(domain: "ImageProbe", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid image dimensions"]))
        }

        // Extract file info
        let fileInfo = try extractFileInfo(from: url)

        // Extract color info
        let colorInfo = extractColorInfo(from: properties, imageSource: imageSource)

        // Build container info
        let container = buildContainerInfo(from: url, fileInfo: fileInfo)

        // Build codec info
        let codec = buildCodecInfo(from: url, imageSource: imageSource)

        // Create a single "video track" descriptor to represent the image
        let videoTrack = VideoTrackDescriptor(
            id: 0,
            trackIndex: 0,
            codec: codec,
            size: CGSize(width: width, height: height),
            displayAspectRatio: Double(width) / Double(height),
            nominalFrameRate: 0, // Images have no frame rate
            minFrameDuration: CMTime.invalid,
            isVFR: false,
            colorInfo: colorInfo,
            timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity),
            timescale: 1,
            averageBitRate: nil
        )

        return MediaDescriptor(
            mediaType: .image,
            container: container,
            duration: CMTime.positiveInfinity, // Images have infinite duration
            timebase: 1,
            videoTracks: [videoTrack],
            audioTracks: [],
            keyframeHint: .allKeyframes, // All frames are keyframes for images
            fileSize: fileInfo.size,
            creationDate: fileInfo.creationDate,
            modificationDate: fileInfo.modificationDate,
            fileName: url.lastPathComponent,
            probeBackend: identifier
        )
    }

    // MARK: - File Info

    private struct FileInfo {
        let size: UInt64?
        let creationDate: Date?
        let modificationDate: Date?
        let contentType: UTType?
    }

    private func extractFileInfo(from url: URL) throws -> FileInfo {
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentTypeKey
        ])

        return FileInfo(
            size: resourceValues.fileSize.map { UInt64($0) },
            creationDate: resourceValues.creationDate,
            modificationDate: resourceValues.contentModificationDate,
            contentType: resourceValues.contentType
        )
    }

    // MARK: - Container Info

    private func buildContainerInfo(from url: URL, fileInfo: FileInfo) -> ContainerInfo {
        let ext = url.pathExtension.lowercased()

        let format: String
        switch ext {
        case "jpg", "jpeg":
            format = "JPEG"
        case "png":
            format = "PNG"
        case "gif":
            format = "GIF"
        case "tiff", "tif":
            format = "TIFF"
        case "heic", "heif":
            format = "HEIC"
        case "webp":
            format = "WebP"
        case "bmp":
            format = "BMP"
        case "ico":
            format = "ICO"
        default:
            format = "Image"
        }

        return ContainerInfo(
            format: format,
            fileExtension: ext,
            uniformTypeIdentifier: fileInfo.contentType?.identifier,
            supportsStreaming: false
        )
    }

    // MARK: - Codec Info

    private func buildCodecInfo(from url: URL, imageSource: CGImageSource) -> CodecInfo {
        // Get UTI from image source
        if let uti = CGImageSourceGetType(imageSource) as String? {
            let displayName: String
            switch uti {
            case "public.jpeg":
                displayName = "JPEG"
            case "public.png":
                displayName = "PNG"
            case "com.compuserve.gif":
                displayName = "GIF"
            case "public.tiff":
                displayName = "TIFF"
            case "public.heic", "public.heif":
                displayName = "HEIC"
            case "org.webmproject.webp":
                displayName = "WebP"
            case "com.microsoft.bmp":
                displayName = "BMP"
            case "com.microsoft.ico":
                displayName = "ICO"
            default:
                displayName = uti
            }
            return CodecInfo(fourCC: String(uti.prefix(4)), displayName: displayName)
        }

        // Fallback to extension
        let ext = url.pathExtension.uppercased()
        return CodecInfo(fourCC: ext, displayName: ext)
    }

    // MARK: - Color Info

    private func extractColorInfo(from properties: [CFString: Any], imageSource: CGImageSource) -> ColorInfo {
        // Try to get color profile information
        var primaries: ColorPrimaries = .bt709
        let transfer: TransferFunction = .sRGB
        var bitDepth = 8

        // Extract bit depth
        if let depth = properties[kCGImagePropertyDepth] as? Int {
            bitDepth = depth
        }

        // Extract color profile name
        if let profileName = properties[kCGImagePropertyProfileName] as? String {
            // Map common profiles to our enums
            if profileName.lowercased().contains("p3") {
                primaries = .p3
            } else if profileName.lowercased().contains("2020") {
                primaries = .bt2020
            } else if profileName.lowercased().contains("adobe") {
                // Adobe RGB - closest mapping is Rec.709 primaries
                primaries = .bt709
            }
        }

        // Check EXIF for color space
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let colorSpaceValue = exif[kCGImagePropertyExifColorSpace] as? Int {
                switch colorSpaceValue {
                case 1:
                    primaries = .bt709 // sRGB
                case 2:
                    primaries = .bt709 // Adobe RGB
                default:
                    break
                }
            }
        }

        return ColorInfo(
            primaries: primaries,
            transferFunction: transfer,
            matrix: nil, // Images don't use YCbCr matrix
            isFullRange: true, // Images typically use full range
            bitDepth: bitDepth,
            chromaSubsampling: nil // Images typically don't have chroma subsampling
        )
    }
}
