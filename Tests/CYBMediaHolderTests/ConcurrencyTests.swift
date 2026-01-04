//
//  ConcurrencyTests.swift
//  CYBMediaHolderTests
//
//  Tests for actor isolation, concurrent access, and thread safety.
//

import XCTest
@testable import CYBMediaHolder

final class ConcurrencyTests: XCTestCase {

    // MARK: - MediaStore Concurrency Tests

    func testMediaStoreConcurrentReads() async {
        let store = MediaStore()

        // Set up some data
        let waveform = WaveformData(
            samplesPerSecond: 100,
            minSamples: [0.1, 0.2, 0.3],
            maxSamples: [0.5, 0.6, 0.7],
            channelCount: 2
        )
        let validity = CacheValidity(version: "1.0", sourceBackend: "Test", sourceHash: nil)
        await store.setWaveform(waveform, validity: validity)

        // Concurrent reads should all succeed
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let hasWaveform = await store.hasWaveform
                    return hasWaveform
                }
            }

            for await result in group {
                XCTAssertTrue(result)
            }
        }
    }

    func testMediaStoreConcurrentWrites() async {
        let store = MediaStore()
        let validity = CacheValidity(version: "1.0", sourceBackend: "Test", sourceHash: nil)

        await withTaskGroup(of: Void.self) { group in
            // Concurrent tag additions
            for i in 0..<50 {
                group.addTask {
                    await store.addTag("tag\(i)")
                }
            }

            // Concurrent marker additions
            for i in 0..<50 {
                group.addTask {
                    await store.setMarker(at: Double(i), label: "marker\(i)")
                }
            }
        }

        // Verify all operations completed
        let annotations = await store.userAnnotations
        XCTAssertEqual(annotations.tags.count, 50)
        XCTAssertEqual(annotations.markers.count, 50)
    }

    func testMediaStoreConcurrentReadWrite() async {
        let store = MediaStore()

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<50 {
                group.addTask {
                    await store.addTag("concurrent\(i)")
                }
            }

            // Readers (running concurrently with writers)
            for _ in 0..<50 {
                group.addTask {
                    _ = await store.userAnnotations.tags
                }
            }
        }

        // Should complete without deadlock or crash
        let annotations = await store.userAnnotations
        XCTAssertEqual(annotations.tags.count, 50)
    }

    // MARK: - InMemoryCache Concurrency Tests

    func testInMemoryCacheConcurrentAccess() async throws {
        let cache = InMemoryMediaCache(maxEntries: 100)

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Concurrent stores
            for i in 0..<50 {
                group.addTask {
                    let key = MediaCacheKey(mediaID: MediaID(), dataType: .waveform)
                    let waveform = WaveformData(
                        samplesPerSecond: i,
                        minSamples: [Float(i)],
                        maxSamples: [Float(i + 1)],
                        channelCount: 1
                    )
                    try await cache.store(waveform, for: key)
                }
            }

            // Concurrent retrieves
            for _ in 0..<50 {
                group.addTask {
                    let key = MediaCacheKey(mediaID: MediaID(), dataType: .peak)
                    _ = try await cache.retrieve(PeakData.self, for: key)
                }
            }

            try await group.waitForAll()
        }

        // Verify cache is in consistent state
        let stats = await cache.statistics()
        XCTAssertTrue(stats.entryCount > 0)
    }

    func testInMemoryCacheLRUUnderConcurrency() async throws {
        let cache = InMemoryMediaCache(maxEntries: 10)

        // Store more items than capacity concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let key = MediaCacheKey(mediaID: MediaID(), dataType: .waveform, variant: "\(i)")
                    let waveform = WaveformData(
                        samplesPerSecond: i,
                        minSamples: [],
                        maxSamples: [],
                        channelCount: 1
                    )
                    try await cache.store(waveform, for: key)
                }
            }

            try await group.waitForAll()
        }

        // Cache should have evicted to stay within limit
        let stats = await cache.statistics()
        XCTAssertLessThanOrEqual(stats.entryCount, 10)
    }

    // MARK: - MediaHolder Concurrency Tests

    func testMediaHolderConcurrentPropertyAccess() async {
        // Create a holder with mock data
        let id = MediaID()
        let locator = MediaLocator.filePath("/test/video.mov")
        let container = ContainerInfo(format: "QuickTime", fileExtension: "mov")
        let descriptor = MediaDescriptor(
            mediaType: .video,
            container: container,
            duration: .zero,
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "Test"
        )

        let holder = MediaHolder(
            id: id,
            locator: locator,
            descriptor: descriptor
        )

        // Concurrent access to immutable properties
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = holder.id
                    _ = holder.displayName
                    _ = holder.duration
                    _ = holder.isVideo
                    _ = holder.baseCapabilities
                }
            }
        }

        // Concurrent access to store (async)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await holder.store.addTag("tag\(i)")
                }
            }
        }

        let annotations = await holder.getAnnotations()
        XCTAssertEqual(annotations.tags.count, 50)
    }

    // MARK: - Task Deduplication Tests

    func testAnalysisTaskDeduplication() async {
        // Note: Full integration test requires actual media files
        // This is a structural test to ensure the pattern works

        let service = MediaAnalysisService.shared

        // Create test holder
        let id = MediaID()
        let locator = MediaLocator.filePath("/nonexistent/test.mov")
        let container = ContainerInfo(format: "QuickTime", fileExtension: "mov")
        let descriptor = MediaDescriptor(
            mediaType: .audio,
            container: container,
            duration: .zero,
            timebase: 600,
            videoTracks: [],
            audioTracks: [],
            probeBackend: "Test"
        )

        let holder = MediaHolder(
            id: id,
            locator: locator,
            descriptor: descriptor
        )

        // Cancel any existing tasks
        await service.cancelAnalysis(for: holder)

        // Verify not analyzing
        let isAnalyzing = await service.isAnalyzing(holder)
        XCTAssertFalse(isAnalyzing)
    }

    // MARK: - ProgressAggregator Tests (via generateAllAnalysis structure)

    func testAnalysisOptionsOptionSet() {
        var options = AnalysisOptions()
        XCTAssertTrue(options.isEmpty)

        options.insert(.waveform)
        XCTAssertTrue(options.contains(.waveform))
        XCTAssertFalse(options.contains(.peak))

        options.insert(.peak)
        XCTAssertTrue(options.contains([.waveform, .peak]))

        // Test preset combinations
        XCTAssertTrue(AnalysisOptions.audio.contains(.waveform))
        XCTAssertTrue(AnalysisOptions.audio.contains(.peak))
        XCTAssertFalse(AnalysisOptions.audio.contains(.keyframeIndex))

        XCTAssertTrue(AnalysisOptions.video.contains(.keyframeIndex))
        XCTAssertFalse(AnalysisOptions.video.contains(.waveform))

        XCTAssertTrue(AnalysisOptions.all.contains(.waveform))
        XCTAssertTrue(AnalysisOptions.all.contains(.peak))
        XCTAssertTrue(AnalysisOptions.all.contains(.keyframeIndex))
        XCTAssertTrue(AnalysisOptions.all.contains(.thumbnailIndex))
    }

    // MARK: - Race Condition Prevention Tests

    func testNoRaceConditionInCacheManager() async throws {
        let memoryCache = InMemoryMediaCache(maxEntries: 50)
        let diskCache = DiskMediaCache(
            cacheDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("RaceTest-\(UUID().uuidString)"),
            maxSizeBytes: 10_000_000,
            maxAge: 3600
        )
        let manager = CacheManager(
            memoryCache: memoryCache,
            diskCache: diskCache,
            configuration: .default
        )

        defer {
            Task {
                await manager.clear()
            }
        }

        // Stress test with many concurrent operations
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                // Stores
                group.addTask {
                    let key = MediaCacheKey(mediaID: MediaID(), dataType: .waveform)
                    let waveform = WaveformData(
                        samplesPerSecond: i,
                        minSamples: [Float(i)],
                        maxSamples: [Float(i + 1)],
                        channelCount: 1
                    )
                    try await manager.store(waveform, for: key)
                }

                // Retrieves
                group.addTask {
                    let key = MediaCacheKey(mediaID: MediaID(), dataType: .peak)
                    _ = try await manager.retrieve(PeakData.self, for: key)
                }

                // Stats reads
                group.addTask {
                    _ = await manager.statistics()
                }
            }

            try await group.waitForAll()
        }

        // Should complete without crash or deadlock
        let stats = await manager.statistics()
        XCTAssertTrue(stats.totalAccesses > 0)
    }
}
