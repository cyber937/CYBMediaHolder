//
//  V1CorrectnessFixTests.swift
//  CYBMediaHolderTests
//
//  Tests for the v1.0.0 correctness fixes:
//  - Drop-frame / non-drop-frame timecode conversion
//  - Content-stable MediaID identity
//  - Color/transfer/matrix CFString mapping
//  - Opt-in signature enforcement
//

import XCTest
import CoreMedia
@testable import CYBMediaHolder

final class V1CorrectnessFixTests: XCTestCase {

    // MARK: - Temp file helper

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CYBV1Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    // MARK: - Timecode conversion (C2/C3)

    func testNonDropFrameConversion() {
        let probe = AVFoundationMediaProbe()

        // 25 fps, non-drop
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 0, frameRate: 25, frameQuanta: 25, dropFrame: false), "00:00:00:00")
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 25, frameRate: 25, frameQuanta: 25, dropFrame: false), "00:00:01:00")
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 1500, frameRate: 25, frameQuanta: 25, dropFrame: false), "00:01:00:00")

        // 24 fps -> one hour
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 86_400, frameRate: 24, frameQuanta: 24, dropFrame: false), "01:00:00:00")
    }

    func testDropFrameConversion() {
        let probe = AVFoundationMediaProbe()

        // 29.97 drop-frame (quanta 30). Uses ";" separator and SMPTE renumbering.
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 0, frameRate: 29.97, frameQuanta: 30, dropFrame: true), "00:00:00;00")
        // Frames 0 and 1 are dropped at minute 1: frame 1798/1799 are still 59;28/59;29.
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 1798, frameRate: 29.97, frameQuanta: 30, dropFrame: true), "00:00:59;28")
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 1800, frameRate: 29.97, frameQuanta: 30, dropFrame: true), "00:01:00;02")
        // No drop at the 10th minute.
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 17_982, frameRate: 29.97, frameQuanta: 30, dropFrame: true), "00:10:00;00")
    }

    func testTimecodeFallsBackToRoundedRateWhenQuantaMissing() {
        let probe = AVFoundationMediaProbe()
        // frameQuanta 0 -> falls back to rounded frameRate (30).
        XCTAssertEqual(probe.frameNumberToTimecode(frameNumber: 30, frameRate: 29.97, frameQuanta: 0, dropFrame: false), "00:00:01:00")
    }

    // MARK: - Content-stable MediaID (C5)

    func testContentStableIdentityIsDeterministic() throws {
        let fileA = tempDir.appendingPathComponent("a.bin")
        try Data(repeating: 0xAB, count: 8192).write(to: fileA)

        let id1 = MediaID.contentStableIdentity(forFileAt: fileA)
        let id2 = MediaID.contentStableIdentity(forFileAt: fileA)
        XCTAssertNotNil(id1)
        XCTAssertEqual(id1?.uuid, id2?.uuid, "Same file must yield the same UUID")
        XCTAssertEqual(id1?.contentHash, id2?.contentHash)
    }

    func testContentStableIdentityDiffersByContent() throws {
        let fileA = tempDir.appendingPathComponent("a.bin")
        let fileB = tempDir.appendingPathComponent("b.bin")
        try Data(repeating: 0xAB, count: 8192).write(to: fileA)
        try Data(repeating: 0xCD, count: 8192).write(to: fileB)

        let a = MediaID.contentStableIdentity(forFileAt: fileA)
        let b = MediaID.contentStableIdentity(forFileAt: fileB)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a?.uuid, b?.uuid, "Different content must yield different UUIDs")
    }

    func testContentStableIdentityNilForNonFileURL() {
        let remote = URL(string: "https://example.com/video.mp4")!
        XCTAssertNil(MediaID.contentStableIdentity(forFileAt: remote))
    }

    func testMediaIDEqualityIsUUIDBased() {
        let uuid = UUID()
        // Same uuid, different content/bookmark hashes -> still equal.
        let m1 = MediaID(uuid: uuid, contentHash: "aaa", bookmarkHash: "x")
        let m2 = MediaID(uuid: uuid, contentHash: "bbb", bookmarkHash: "y")
        XCTAssertEqual(m1, m2)
        XCTAssertEqual(m1.hashValue, m2.hashValue)

        // Different uuids -> not equal.
        let m3 = MediaID(uuid: UUID(), contentHash: "aaa")
        XCTAssertNotEqual(m1, m3)
    }

    // MARK: - Color CFString mapping (C1 / matrix fix)

    func testColorPrimariesMapping() {
        XCTAssertEqual(ColorPrimaries(from: "ITU_R_709_2" as CFString), .bt709)
        XCTAssertEqual(ColorPrimaries(from: "ITU_R_2020" as CFString), .bt2020)
        XCTAssertEqual(ColorPrimaries(from: "P3_D65" as CFString), .p3)
        XCTAssertEqual(ColorPrimaries(from: nil), .unknown)
    }

    func testTransferFunctionMapping() {
        XCTAssertEqual(TransferFunction(from: "ITU_R_2100_HLG" as CFString), .hlg)
        XCTAssertEqual(TransferFunction(from: "SMPTE_ST_2084_PQ" as CFString), .pq)
        XCTAssertEqual(TransferFunction(from: "ITU_R_709_2" as CFString), .bt709)
        XCTAssertTrue(TransferFunction.hlg.isHDR)
        XCTAssertTrue(TransferFunction.pq.isHDR)
        XCTAssertFalse(TransferFunction.bt709.isHDR)
    }

    func testMatrixCoefficientsMapping() {
        XCTAssertEqual(MatrixCoefficients(from: "ITU_R_709_2" as CFString), .bt709)
        XCTAssertEqual(MatrixCoefficients(from: "ITU_R_2020" as CFString), .bt2020NCL)
        // The real BT.601 matrix value (previously mis-keyed as "SMPTE_170M_2004").
        XCTAssertEqual(MatrixCoefficients(from: "ITU_R_601_4" as CFString), .bt601)
    }

    // MARK: - Opt-in signature enforcement

    func testSignatureMismatchToleratedByDefault() throws {
        let fakeMp4 = tempDir.appendingPathComponent("disguised.mp4")
        try pngHeader().write(to: fakeMp4)

        // Default config detects but does not reject the mismatch.
        let validator = MediaFileValidator(config: .default)
        XCTAssertNoThrow(try validator.validate(url: fakeMp4))
    }

    func testSignatureMismatchRejectedWhenEnforced() throws {
        let fakeMp4 = tempDir.appendingPathComponent("disguised.mp4")
        try pngHeader().write(to: fakeMp4)

        let config = MediaValidationConfig(enforceSignatureMatching: true)
        let validator = MediaFileValidator(config: config)
        XCTAssertThrowsError(try validator.validate(url: fakeMp4)) { error in
            guard case MediaValidationError.signatureMismatch = error else {
                return XCTFail("Expected signatureMismatch, got \(error)")
            }
        }
    }

    func testMatchingSignatureNotRejectedWhenEnforced() throws {
        let realPng = tempDir.appendingPathComponent("real.png")
        try pngHeader().write(to: realPng)

        let config = MediaValidationConfig(enforceSignatureMatching: true)
        let validator = MediaFileValidator(config: config)
        XCTAssertNoThrow(try validator.validate(url: realPng))
    }

    // MARK: - Helpers

    /// A minimal valid PNG magic-number header padded to a non-trivial size.
    private func pngHeader() -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(Data(repeating: 0x00, count: 64))
        return data
    }
}
