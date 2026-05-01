//
//  MediaProbeRegistryFallbackTests.swift
//  CYBMediaHolderTests
//
//  Tests for MediaProbeRegistry's fallback chain behavior.
//

import XCTest
import CoreMedia
@testable import CYBMediaHolder

final class MediaProbeRegistryFallbackTests: XCTestCase {

    func testFallbackOnRecoverableError() async throws {
        let registry = MediaProbeRegistry(empty: ())

        // First probe fails with a recoverable error (codec/format failure)
        let failingProbe = ConfigurableMockProbe(
            identifier: "primary",
            supportedExtensions: ["mxf"],
            error: .propertyLoadFailed(NSError(domain: "test", code: -1))
        )

        // Second probe succeeds
        let succeedingProbe = ConfigurableMockProbe(
            identifier: "fallback",
            supportedExtensions: ["mxf"],
            descriptor: makeDescriptor(probeBackend: "fallback")
        )

        await registry.register(failingProbe)
        await registry.register(succeedingProbe)

        let locator = MediaLocator.filePath("/tmp/test.mxf")
        let descriptor = try await registry.probe(locator: locator)

        XCTAssertEqual(descriptor.probeBackend, "fallback",
                       "Registry should fall back to second probe when first fails recoverably")
    }

    func testNoFallbackOnFileNotFound() async throws {
        let registry = MediaProbeRegistry(empty: ())

        let firstProbe = ConfigurableMockProbe(
            identifier: "primary",
            supportedExtensions: ["mxf"],
            error: .fileNotFound("/missing")
        )

        let secondProbe = ConfigurableMockProbe(
            identifier: "fallback",
            supportedExtensions: ["mxf"],
            descriptor: makeDescriptor(probeBackend: "fallback")
        )

        await registry.register(firstProbe)
        await registry.register(secondProbe)

        let locator = MediaLocator.filePath("/tmp/test.mxf")
        do {
            _ = try await registry.probe(locator: locator)
            XCTFail("Should have thrown fileNotFound — non-recoverable errors must not fall back")
        } catch let error as MediaProbeError {
            if case .fileNotFound = error {
                // ok
            } else {
                XCTFail("Expected fileNotFound, got \(error)")
            }
        }
    }

    func testThrowsLastRecoverableErrorWhenAllFail() async throws {
        let registry = MediaProbeRegistry(empty: ())

        let firstProbe = ConfigurableMockProbe(
            identifier: "primary",
            supportedExtensions: ["mxf"],
            error: .propertyLoadFailed(NSError(domain: "first", code: 1))
        )

        let secondProbe = ConfigurableMockProbe(
            identifier: "fallback",
            supportedExtensions: ["mxf"],
            error: .noTracksFound
        )

        await registry.register(firstProbe)
        await registry.register(secondProbe)

        let locator = MediaLocator.filePath("/tmp/test.mxf")
        do {
            _ = try await registry.probe(locator: locator)
            XCTFail("Should throw when every probe fails")
        } catch let error as MediaProbeError {
            if case .noTracksFound = error {
                // ok — last recoverable error wins
            } else {
                XCTFail("Expected noTracksFound (last error), got \(error)")
            }
        }
    }

    func testIsCodecOrFormatFailureClassification() {
        XCTAssertTrue(MediaProbeError.unsupportedFormat("x").isCodecOrFormatFailure)
        XCTAssertTrue(MediaProbeError.notPlayable(reason: "x").isCodecOrFormatFailure)
        XCTAssertTrue(MediaProbeError.propertyLoadFailed(NSError(domain: "x", code: 0)).isCodecOrFormatFailure)
        XCTAssertTrue(MediaProbeError.noTracksFound.isCodecOrFormatFailure)
        XCTAssertTrue(MediaProbeError.probeFailed(NSError(domain: "x", code: 0)).isCodecOrFormatFailure)

        XCTAssertFalse(MediaProbeError.fileNotFound("x").isCodecOrFormatFailure)
        XCTAssertFalse(MediaProbeError.locatorResolutionFailed(NSError(domain: "x", code: 0)).isCodecOrFormatFailure)
        XCTAssertFalse(MediaProbeError.accessDenied.isCodecOrFormatFailure)
    }

    // MARK: - Helpers

    private func makeDescriptor(probeBackend: String) -> MediaDescriptor {
        MediaDescriptor(
            mediaType: .video,
            container: ContainerInfo(format: "MXF", fileExtension: "mxf"),
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: probeBackend
        )
    }
}

// MARK: - Configurable Mock Probe

/// Probe with configurable supportedExtensions / outcome — enables fallback testing.
private struct ConfigurableMockProbe: MediaProbe, Sendable {
    let identifier: String
    let displayName: String
    let supportedExtensions: Set<String>
    let supportedUTTypes: Set<String>
    let descriptor: MediaDescriptor?
    let error: MediaProbeError?

    init(
        identifier: String,
        supportedExtensions: Set<String>,
        descriptor: MediaDescriptor? = nil,
        error: MediaProbeError? = nil
    ) {
        self.identifier = identifier
        self.displayName = identifier
        self.supportedExtensions = supportedExtensions
        self.supportedUTTypes = []
        self.descriptor = descriptor
        self.error = error
    }

    func probe(locator: MediaLocator) async throws -> MediaDescriptor {
        if let error = error { throw error }
        guard let descriptor = descriptor else { throw MediaProbeError.noTracksFound }
        return descriptor
    }
}
