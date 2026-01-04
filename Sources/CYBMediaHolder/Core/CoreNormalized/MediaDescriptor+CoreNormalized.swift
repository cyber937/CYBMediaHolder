//
//  MediaDescriptor+CoreNormalized.swift
//  CYBMediaHolder
//
//  Extension to generate CoreNormalizedStore from MediaDescriptor.
//  Bridges existing model to core/* normalization layer.
//

import Foundation

// MARK: - MediaDescriptor Extension

extension MediaDescriptor {

    /// Creates a `CoreNormalizedStore` from this descriptor.
    ///
    /// Extracts available metadata and populates the store with
    /// appropriate `CoreKey` entries. Keys without corresponding
    /// data are not added to the store.
    ///
    /// - Parameter source: Provenance source identifier (default: uses `probeBackend`).
    /// - Returns: A populated `CoreNormalizedStore`.
    ///
    /// ## Populated Keys
    /// - Container: format, duration, track count
    /// - Video: codec, dimensions, frame rate, color info
    /// - Audio: track count, channels, sample rate
    ///
    /// ## Not Populated (Future)
    /// - `core/timecode.*`: Requires dedicated timecode extraction
    /// - `core/asset.fingerprint`: Requires content hashing
    public func makeCoreNormalizedStore(source: String? = nil) -> CoreNormalizedStore {
        var store = CoreNormalizedStore()
        let provenance = CoreProvenance(source: source ?? probeBackend)

        // MARK: - Container Properties

        store.addCandidate(
            .containerFormat,
            CoreCandidate(value: .string(container.format), provenance: provenance)
        )

        store.addCandidate(
            .containerDurationSeconds,
            CoreCandidate(value: .double(durationSeconds), provenance: provenance)
        )

        store.addCandidate(
            .containerTrackCount,
            CoreCandidate(value: .int(totalTrackCount), provenance: provenance)
        )

        if let fileSize = fileSize {
            store.addCandidate(
                .containerSizeBytes,
                CoreCandidate(value: .int64(Int64(fileSize)), provenance: provenance)
            )
        }

        // MARK: - Video Properties (Primary Track)

        if let video = primaryVideoTrack {
            store.addCandidate(
                .videoCodec,
                CoreCandidate(value: .string(video.codec.fourCC), provenance: provenance)
            )

            store.addCandidate(
                .videoWidth,
                CoreCandidate(value: .int(Int(video.size.width)), provenance: provenance)
            )

            store.addCandidate(
                .videoHeight,
                CoreCandidate(value: .int(Int(video.size.height)), provenance: provenance)
            )

            store.addCandidate(
                .videoFPS,
                CoreCandidate(value: .double(Double(video.nominalFrameRate)), provenance: provenance)
            )

            // Scan type: simplified detection (VFR check or default to progressive)
            let scanType = video.isVFR ? "variable" : "progressive"
            store.addCandidate(
                .videoScan,
                CoreCandidate(value: .string(scanType), provenance: provenance)
            )

            // Bit depth from color info
            if let bitDepth = video.colorInfo.bitDepth {
                store.addCandidate(
                    .videoBitDepth,
                    CoreCandidate(value: .int(bitDepth), provenance: provenance)
                )
            }

            // Chroma subsampling
            if let chroma = video.colorInfo.chromaSubsampling {
                store.addCandidate(
                    .videoChroma,
                    CoreCandidate(value: .string(chroma.rawValue), provenance: provenance)
                )
            }

            // MARK: - Color Properties

            if let primaries = video.colorInfo.primaries, primaries != .unknown {
                store.addCandidate(
                    .colorPrimaries,
                    CoreCandidate(value: .string(primaries.rawValue), provenance: provenance)
                )
            }

            if let transfer = video.colorInfo.transferFunction, transfer != .unknown {
                store.addCandidate(
                    .colorTransfer,
                    CoreCandidate(value: .string(transfer.rawValue), provenance: provenance)
                )
            }

            if let matrix = video.colorInfo.matrix, matrix != .unknown {
                store.addCandidate(
                    .colorMatrix,
                    CoreCandidate(value: .string(matrix.rawValue), provenance: provenance)
                )
            }

            if let isFullRange = video.colorInfo.isFullRange {
                store.addCandidate(
                    .colorRange,
                    CoreCandidate(
                        value: .string(isFullRange ? "full" : "limited"),
                        provenance: provenance
                    )
                )
            }

            store.addCandidate(
                .colorHDR,
                CoreCandidate(value: .bool(video.colorInfo.isHDR), provenance: provenance)
            )
        }

        // MARK: - Audio Properties

        store.addCandidate(
            .audioTrackCount,
            CoreCandidate(value: .int(audioTracks.count), provenance: provenance)
        )

        if let audio = primaryAudioTrack {
            store.addCandidate(
                .audioChannels,
                CoreCandidate(value: .int(audio.channelCount), provenance: provenance)
            )

            store.addCandidate(
                .audioSampleRateHz,
                CoreCandidate(value: .double(audio.sampleRate), provenance: provenance)
            )

            if let bitDepth = audio.bitsPerSample {
                store.addCandidate(
                    .audioBitDepth,
                    CoreCandidate(value: .int(bitDepth), provenance: provenance)
                )
            }
        }

        return store
    }

    /// Creates a `CoreNormalizedStore` from this descriptor with timecode information.
    ///
    /// This method includes timecode data in addition to standard descriptor metadata.
    ///
    /// - Parameters:
    ///   - timecode: The extracted timecode information.
    ///   - source: Provenance source identifier (default: uses `probeBackend`).
    /// - Returns: A populated `CoreNormalizedStore` including timecode keys.
    public func makeCoreNormalizedStore(
        timecode: TimecodeExtractionResult,
        source: String? = nil
    ) -> CoreNormalizedStore {
        var store = makeCoreNormalizedStore(source: source)

        // Create provenance with timecode-specific source and confidence
        let timecodeProvenance = CoreProvenance(
            source: "avfoundation:\(timecode.sourceKind)",
            confidence: timecode.confidence
        )

        // Add timecode candidates
        store.addCandidate(
            .timecodeStart,
            CoreCandidate(value: .string(timecode.start), provenance: timecodeProvenance)
        )

        store.addCandidate(
            .timecodeRate,
            CoreCandidate(value: .double(timecode.rate), provenance: timecodeProvenance)
        )

        store.addCandidate(
            .timecodeDropFrame,
            CoreCandidate(value: .bool(timecode.dropFrame), provenance: timecodeProvenance)
        )

        store.addCandidate(
            .timecodeSourceKind,
            CoreCandidate(value: .string(timecode.sourceKind), provenance: timecodeProvenance)
        )

        store.addCandidate(
            .timecodeSource,
            CoreCandidate(value: .string(timecode.source), provenance: timecodeProvenance)
        )

        return store
    }
}

// MARK: - ExtendedProbeResult Extension

extension ExtendedProbeResult {

    /// Creates a `CoreNormalizedStore` from this extended probe result.
    ///
    /// Includes both descriptor metadata and timecode information.
    ///
    /// - Parameter source: Provenance source identifier (default: uses probe backend).
    /// - Returns: A populated `CoreNormalizedStore` with all metadata.
    public func makeCoreNormalizedStore(source: String? = nil) -> CoreNormalizedStore {
        descriptor.makeCoreNormalizedStore(timecode: timecode, source: source)
    }
}

// MARK: - MediaHolder Extension

extension MediaHolder {

    /// Creates a `CoreNormalizedStore` from this holder's descriptor.
    ///
    /// Adds asset identity keys in addition to descriptor metadata.
    ///
    /// - Parameter source: Provenance source identifier (default: uses probe backend).
    /// - Returns: A populated `CoreNormalizedStore`.
    public func makeCoreNormalizedStore(source: String? = nil) -> CoreNormalizedStore {
        var store = descriptor.makeCoreNormalizedStore(source: source)
        let provenance = CoreProvenance(source: source ?? descriptor.probeBackend)

        // Add asset identity
        store.addCandidate(
            .assetId,
            CoreCandidate(value: .string(id.uuid.uuidString), provenance: provenance)
        )

        // Add URI from locator
        store.addCandidate(
            .assetURI,
            CoreCandidate(value: .string(locator.description), provenance: provenance)
        )

        // Add fingerprint if available
        if let hash = id.contentHash {
            store.addCandidate(
                .assetFingerprint,
                CoreCandidate(value: .string(hash), provenance: provenance)
            )
        }

        return store
    }
}
