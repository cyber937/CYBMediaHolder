//
//  MediaFileValidatorTests.swift
//  CYBMediaHolderTests
//
//  Tests for MediaFileValidator input validation.
//

import XCTest
@testable import CYBMediaHolder

final class MediaFileValidatorTests: XCTestCase {

    var tempDirectory: URL!
    var validator: MediaFileValidator!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        validator = MediaFileValidator()
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - File Existence Tests

    func testValidateNonexistentFile() throws {
        let nonexistentPath = tempDirectory.appendingPathComponent("nonexistent.mp4").path

        XCTAssertThrowsError(try validator.validate(path: nonexistentPath)) { error in
            guard case MediaValidationError.fileNotFound = error else {
                XCTFail("Expected fileNotFound error, got \(error)")
                return
            }
        }
    }

    func testValidateExistingFile() throws {
        // Create a valid test file with MP4 signature
        let testFile = tempDirectory.appendingPathComponent("test.mp4")
        let mp4Header = createMP4Header()
        try mp4Header.write(to: testFile)

        XCTAssertNoThrow(try validator.validate(url: testFile))
    }

    // MARK: - Empty File Tests

    func testValidateEmptyFile() throws {
        let emptyFile = tempDirectory.appendingPathComponent("empty.mp4")
        try Data().write(to: emptyFile)

        XCTAssertThrowsError(try validator.validate(url: emptyFile)) { error in
            guard case MediaValidationError.emptyFile = error else {
                XCTFail("Expected emptyFile error, got \(error)")
                return
            }
        }
    }

    // MARK: - File Size Tests

    func testValidateFileTooLarge() throws {
        // Create validator with small size limit
        let smallLimitConfig = MediaValidationConfig(maxFileSize: 100)
        let limitedValidator = MediaFileValidator(config: smallLimitConfig)

        // Create a file larger than the limit
        let largeFile = tempDirectory.appendingPathComponent("large.mp4")
        let largeData = Data(repeating: 0, count: 200)
        try largeData.write(to: largeFile)

        XCTAssertThrowsError(try limitedValidator.validate(url: largeFile)) { error in
            guard case MediaValidationError.fileTooLarge(let size, let maxSize) = error else {
                XCTFail("Expected fileTooLarge error, got \(error)")
                return
            }
            XCTAssertEqual(size, 200)
            XCTAssertEqual(maxSize, 100)
        }
    }

    func testValidateFileWithinSizeLimit() throws {
        let config = MediaValidationConfig(maxFileSize: 1000)
        let limitedValidator = MediaFileValidator(config: config)

        let smallFile = tempDirectory.appendingPathComponent("small.mp4")
        let smallData = createMP4Header()
        try smallData.write(to: smallFile)

        XCTAssertNoThrow(try limitedValidator.validate(url: smallFile))
    }

    // MARK: - Symbolic Link Tests

    func testValidateSymbolicLink() throws {
        // Create a real file
        let realFile = tempDirectory.appendingPathComponent("real.mp4")
        try createMP4Header().write(to: realFile)

        // Create a symlink to it
        let symlinkFile = tempDirectory.appendingPathComponent("symlink.mp4")
        try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: realFile)

        XCTAssertThrowsError(try validator.validate(url: symlinkFile)) { error in
            guard case MediaValidationError.symbolicLinkNotAllowed = error else {
                XCTFail("Expected symbolicLinkNotAllowed error, got \(error)")
                return
            }
        }
    }

    func testValidateSymbolicLinkAllowedWithRelaxedConfig() throws {
        // Create a real file
        let realFile = tempDirectory.appendingPathComponent("real2.mp4")
        try createMP4Header().write(to: realFile)

        // Create a symlink to it
        let symlinkFile = tempDirectory.appendingPathComponent("symlink2.mp4")
        try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: realFile)

        // Use relaxed config that allows symlinks
        let relaxedValidator = MediaFileValidator(config: .relaxed)
        XCTAssertNoThrow(try relaxedValidator.validate(url: symlinkFile))
    }

    // MARK: - Path Safety Tests

    func testValidatePathWithTraversal() throws {
        let unsafePath = "/tmp/../etc/passwd"

        XCTAssertThrowsError(try validator.validate(path: unsafePath)) { error in
            guard case MediaValidationError.unsafePathComponents = error else {
                XCTFail("Expected unsafePathComponents error, got \(error)")
                return
            }
        }
    }

    func testValidateRelativePath() throws {
        let relativePath = "relative/path/file.mp4"

        XCTAssertThrowsError(try validator.validate(path: relativePath)) { error in
            guard case MediaValidationError.unsafePathComponents = error else {
                XCTFail("Expected unsafePathComponents error, got \(error)")
                return
            }
        }
    }

    // MARK: - File Signature Detection Tests

    func testDetectMP4Signature() throws {
        let mp4File = tempDirectory.appendingPathComponent("test.mp4")
        try createMP4Header().write(to: mp4File)

        let signature = try validator.detectSignature(url: mp4File)
        XCTAssertEqual(signature, .mp4)
        XCTAssertTrue(signature.isVideo)
    }

    func testDetectMOVSignature() throws {
        let movFile = tempDirectory.appendingPathComponent("test.mov")
        try createMOVHeader().write(to: movFile)

        let signature = try validator.detectSignature(url: movFile)
        XCTAssertEqual(signature, .mov)
        XCTAssertTrue(signature.isVideo)
    }

    func testDetectJPEGSignature() throws {
        let jpegFile = tempDirectory.appendingPathComponent("test.jpg")
        try createJPEGHeader().write(to: jpegFile)

        let signature = try validator.detectSignature(url: jpegFile)
        XCTAssertEqual(signature, .jpeg)
        XCTAssertTrue(signature.isImage)
    }

    func testDetectPNGSignature() throws {
        let pngFile = tempDirectory.appendingPathComponent("test.png")
        try createPNGHeader().write(to: pngFile)

        let signature = try validator.detectSignature(url: pngFile)
        XCTAssertEqual(signature, .png)
        XCTAssertTrue(signature.isImage)
    }

    func testDetectMP3Signature() throws {
        let mp3File = tempDirectory.appendingPathComponent("test.mp3")
        try createMP3Header().write(to: mp3File)

        let signature = try validator.detectSignature(url: mp3File)
        XCTAssertEqual(signature, .mp3)
        XCTAssertTrue(signature.isAudio)
    }

    func testDetectWAVSignature() throws {
        let wavFile = tempDirectory.appendingPathComponent("test.wav")
        try createWAVHeader().write(to: wavFile)

        let signature = try validator.detectSignature(url: wavFile)
        XCTAssertEqual(signature, .wav)
        XCTAssertTrue(signature.isAudio)
    }

    func testDetectUnknownSignature() throws {
        let unknownFile = tempDirectory.appendingPathComponent("test.xyz")
        try Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B]).write(to: unknownFile)

        let signature = try validator.detectSignature(url: unknownFile)
        XCTAssertEqual(signature, .unknown)
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = MediaValidationConfig.default

        XCTAssertEqual(config.maxFileSize, 100 * 1024 * 1024 * 1024) // 100 GB
        XCTAssertTrue(config.rejectSymlinks)
        XCTAssertTrue(config.validateSignature)
        XCTAssertTrue(config.checkPathSafety)
    }

    func testRelaxedConfiguration() {
        let config = MediaValidationConfig.relaxed

        XCTAssertEqual(config.maxFileSize, 500 * 1024 * 1024 * 1024) // 500 GB
        XCTAssertFalse(config.rejectSymlinks)
        XCTAssertFalse(config.validateSignature)
        XCTAssertFalse(config.checkPathSafety)
    }

    // MARK: - URL Extension Tests

    func testURLValidationExtension() throws {
        let validFile = tempDirectory.appendingPathComponent("valid.mp4")
        try createMP4Header().write(to: validFile)

        XCTAssertNoThrow(try validFile.validateForMediaLoading())
    }

    func testURLValidationExtensionWithConfig() throws {
        let validFile = tempDirectory.appendingPathComponent("valid2.mp4")
        try createMP4Header().write(to: validFile)

        XCTAssertNoThrow(try validFile.validateForMediaLoading(config: .relaxed))
    }

    // MARK: - Helper Methods

    private func createMP4Header() -> Data {
        // ftyp box: size (4) + type (4) + brand (4)
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14]) // size = 20
        data.append(contentsOf: Array("ftyp".utf8))
        data.append(contentsOf: Array("isom".utf8))
        data.append(contentsOf: [0x00, 0x00, 0x02, 0x00]) // minor version
        data.append(contentsOf: Array("isom".utf8))
        return data
    }

    private func createMOVHeader() -> Data {
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14]) // size = 20
        data.append(contentsOf: Array("ftyp".utf8))
        data.append(contentsOf: Array("qt  ".utf8)) // QuickTime brand
        data.append(contentsOf: [0x00, 0x00, 0x02, 0x00])
        data.append(contentsOf: Array("qt  ".utf8))
        return data
    }

    private func createJPEGHeader() -> Data {
        return Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
    }

    private func createPNGHeader() -> Data {
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
    }

    private func createMP3Header() -> Data {
        // ID3 header
        return Data(Array("ID3".utf8) + [0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    private func createWAVHeader() -> Data {
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: [0x24, 0x00, 0x00, 0x00]) // file size
        data.append(contentsOf: Array("WAVE".utf8))
        return data
    }
}
