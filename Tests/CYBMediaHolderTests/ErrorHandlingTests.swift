//
//  ErrorHandlingTests.swift
//  CYBMediaHolderTests
//
//  Tests for error type descriptions and CustomStringConvertible conformance.
//

import XCTest
@testable import CYBMediaHolder

final class ErrorHandlingTests: XCTestCase {

    // MARK: - MediaProbeError Tests

    func testMediaProbeErrorDescriptions() {
        XCTAssertEqual(
            MediaProbeError.fileNotFound("/path/to/file.mov").description,
            "File not found: /path/to/file.mov"
        )

        XCTAssertEqual(
            MediaProbeError.noTracksFound.description,
            "No media tracks found in file"
        )

        XCTAssertEqual(
            MediaProbeError.accessDenied.description,
            "Security access denied (sandbox restriction)"
        )

        XCTAssertEqual(
            MediaProbeError.unsupportedFormat("mkv").description,
            "Unsupported format: mkv"
        )

        XCTAssertEqual(
            MediaProbeError.notPlayable(reason: "Encrypted content").description,
            "Media not playable: Encrypted content"
        )

        let underlyingError = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        XCTAssertTrue(
            MediaProbeError.propertyLoadFailed(underlyingError).description.contains("Property load failed")
        )

        XCTAssertTrue(
            MediaProbeError.locatorResolutionFailed(underlyingError).description.contains("Locator resolution failed")
        )

        XCTAssertTrue(
            MediaProbeError.probeFailed(underlyingError).description.contains("Probe failed")
        )
    }

    // MARK: - MediaAnalysisError Tests

    func testMediaAnalysisErrorDescriptions() {
        XCTAssertEqual(
            MediaAnalysisError.noAudioTrack.description,
            "No audio track available for analysis"
        )

        XCTAssertEqual(
            MediaAnalysisError.noVideoTrack.description,
            "No video track available for analysis"
        )

        XCTAssertEqual(
            MediaAnalysisError.cancelled.description,
            "Analysis was cancelled"
        )

        let underlyingError = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Read error"])
        XCTAssertTrue(
            MediaAnalysisError.audioReadFailed(underlyingError).description.contains("Audio read failed")
        )

        XCTAssertTrue(
            MediaAnalysisError.videoReadFailed(underlyingError).description.contains("Video read failed")
        )

        XCTAssertTrue(
            MediaAnalysisError.locatorResolutionFailed(underlyingError).description.contains("Locator resolution failed")
        )

        XCTAssertTrue(
            MediaAnalysisError.analysisFailed(underlyingError).description.contains("Analysis failed")
        )
    }

    // MARK: - MediaCacheError Tests

    func testMediaCacheErrorDescriptions() {
        XCTAssertEqual(
            MediaCacheError.storageFull.description,
            "Cache storage is full"
        )

        XCTAssertEqual(
            MediaCacheError.expired.description,
            "Cache entry has expired"
        )

        let underlyingError = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])
        XCTAssertTrue(
            MediaCacheError.encodingFailed(underlyingError).description.contains("Cache encoding failed")
        )

        XCTAssertTrue(
            MediaCacheError.decodingFailed(underlyingError).description.contains("Cache decoding failed")
        )

        XCTAssertTrue(
            MediaCacheError.ioError(underlyingError).description.contains("Cache I/O error")
        )
    }

    // MARK: - ResolutionError Tests

    func testResolutionErrorDescriptions() {
        XCTAssertEqual(
            MediaLocator.ResolutionError.fileNotFound(path: "/missing/file.mov").description,
            "File not found: /missing/file.mov"
        )

        XCTAssertEqual(
            MediaLocator.ResolutionError.unsupportedLocatorType.description,
            "Unsupported locator type"
        )

        // Bookmark stale with full context
        let staleError = MediaLocator.ResolutionError.bookmarkStale(
            originalPath: "/original/path.mov",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(staleError.description.contains("Bookmark is stale"))
        XCTAssertTrue(staleError.description.contains("/original/path.mov"))

        // Bookmark stale with partial context
        let partialStale = MediaLocator.ResolutionError.bookmarkStale(originalPath: nil, createdAt: nil)
        XCTAssertEqual(partialStale.description, "Bookmark is stale")

        // Security scope denied
        let url = URL(fileURLWithPath: "/secure/file.mov")
        XCTAssertTrue(
            MediaLocator.ResolutionError.securityScopeAccessDenied(url: url).description
                .contains("Security scope access denied")
        )

        // Network not implemented
        let httpURL = URL(string: "https://example.com/video.mp4")!
        XCTAssertTrue(
            MediaLocator.ResolutionError.networkNotImplemented(url: httpURL).description
                .contains("Network access not implemented")
        )

        XCTAssertEqual(
            MediaLocator.ResolutionError.networkNotImplemented(url: nil).description,
            "Network access not implemented"
        )

        // Bookmark resolution failed
        let bookmarkError = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Invalid bookmark"])
        XCTAssertTrue(
            MediaLocator.ResolutionError.bookmarkResolutionFailed(underlyingError: bookmarkError).description
                .contains("Bookmark resolution failed")
        )
    }

    // MARK: - MigrationError Tests

    func testMigrationErrorDescriptions() {
        XCTAssertEqual(
            MigrationError.sourceOffline.description,
            "Source media is in offline state"
        )

        XCTAssertEqual(
            MigrationError.locationResolutionFailed.description,
            "Failed to resolve file location"
        )

        XCTAssertEqual(
            MigrationError.unsupportedMediaType.description,
            "Unsupported media type"
        )

        XCTAssertEqual(
            MigrationError.missingData("bookmark").description,
            "Missing required data: bookmark"
        )

        let underlyingError = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Probe error"])
        XCTAssertTrue(
            MigrationError.probeFailed(underlyingError).description.contains("Media probe failed")
        )
    }

    // MARK: - Error Localization

    func testErrorsAreLocalizable() {
        // All errors should have localizedDescription from description
        let probeError: Error = MediaProbeError.noTracksFound
        XCTAssertFalse(probeError.localizedDescription.isEmpty)

        let analysisError: Error = MediaAnalysisError.cancelled
        XCTAssertFalse(analysisError.localizedDescription.isEmpty)

        let cacheError: Error = MediaCacheError.expired
        XCTAssertFalse(cacheError.localizedDescription.isEmpty)
    }
}
