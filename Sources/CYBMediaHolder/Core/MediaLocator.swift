//
//  MediaLocator.swift
//  CYBMediaHolder
//
//  Abstraction for media location, supporting local files, security-scoped bookmarks,
//  and future remote sources (HTTP, S3, etc.).
//

import Foundation

/// Represents the location of a media resource.
///
/// `MediaLocator` abstracts the source of media, enabling:
/// - Local file access with path or security-scoped bookmark
/// - Future HTTP/HTTPS streaming
/// - Future cloud storage (S3, GCS, etc.)
/// - Future MAM system references
///
/// ## Design Notes
/// - All cases that require network access should be clearly distinguished
/// - Security-scoped bookmarks are essential for macOS sandbox
/// - The `resolved` property provides async URL resolution for all types
///
/// ## Future Extensions
/// - `.httpRange(url:)`: HTTP with Range header support
/// - `.s3(bucket:key:region:)`: AWS S3 object
/// - `.mamReference(assetID:)`: MAM system asset reference
public enum MediaLocator: Hashable, Codable, Sendable {

    /// Local file path.
    /// - Note: May fail if file is moved or deleted.
    case filePath(String)

    /// Security-scoped bookmark data (macOS sandbox).
    /// - Note: Preferred for sandboxed apps; survives file moves within same volume.
    case securityScopedBookmark(Data)

    /// Direct URL (file:// or future http(s)://).
    /// - Note: For file URLs, prefer `filePath` or `securityScopedBookmark`.
    case url(URL)

    /// HTTP(S) URL with optional range request support.
    /// - Note: For future streaming/remote media support.
    case http(url: URL, supportsRangeRequests: Bool)

    /// Placeholder for future S3/cloud storage.
    /// - Note: Not implemented in v1; included for API stability.
    case s3(bucket: String, key: String, region: String)

    // MARK: - Convenience Initializers

    /// Creates a locator from a file URL.
    ///
    /// - Parameter fileURL: A file:// URL.
    /// - Returns: A `.filePath` locator, or nil if not a file URL.
    public static func fromFileURL(_ fileURL: URL) -> MediaLocator? {
        guard fileURL.isFileURL else { return nil }
        return .filePath(fileURL.path)
    }

    /// Creates a security-scoped bookmark locator from a URL.
    ///
    /// - Parameter url: The URL to create a bookmark for.
    /// - Returns: A `.securityScopedBookmark` locator.
    /// - Throws: If bookmark creation fails.
    public static func fromSecurityScopedURL(_ url: URL) throws -> MediaLocator {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return .securityScopedBookmark(bookmarkData)
    }

    // MARK: - Properties

    /// Whether this locator refers to a local resource.
    public var isLocal: Bool {
        switch self {
        case .filePath, .securityScopedBookmark:
            return true
        case .url(let url):
            return url.isFileURL
        case .http, .s3:
            return false
        }
    }

    /// Whether this locator requires network access.
    public var requiresNetwork: Bool {
        switch self {
        case .filePath, .securityScopedBookmark:
            return false
        case .url(let url):
            return !url.isFileURL
        case .http, .s3:
            return true
        }
    }

    /// The file path, if this is a local file locator.
    public var filePath: String? {
        switch self {
        case .filePath(let path):
            return path
        case .url(let url) where url.isFileURL:
            return url.path
        default:
            return nil
        }
    }
}

// MARK: - URL Resolution

extension MediaLocator {

    /// Result of URL resolution, including cleanup action.
    public struct ResolvedURL: Sendable {
        /// The resolved URL.
        public let url: URL

        /// Whether security-scoped access was started.
        public let isSecurityScoped: Bool

        /// Call this when done accessing the resource.
        public func stopAccessing() {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    /// Errors that can occur during URL resolution.
    public enum ResolutionError: Error, Sendable, CustomStringConvertible {
        /// File was not found at the specified path.
        case fileNotFound(path: String)

        /// Security-scoped bookmark has become stale and needs to be recreated.
        /// - Parameters:
        ///   - originalPath: The original path the bookmark was created for, if available.
        ///   - createdAt: When the bookmark was created, if available.
        case bookmarkStale(originalPath: String?, createdAt: Date?)

        /// Failed to resolve the bookmark data to a URL.
        case bookmarkResolutionFailed(underlyingError: Error)

        /// Security scope access was denied by the system.
        /// - Parameter url: The URL that was denied access.
        case securityScopeAccessDenied(url: URL)

        /// The locator type is not supported for this operation.
        case unsupportedLocatorType

        /// Network operations are not yet implemented.
        /// - Parameter url: The remote URL that was attempted.
        case networkNotImplemented(url: URL?)

        public var description: String {
            switch self {
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .bookmarkStale(let originalPath, let createdAt):
                var msg = "Bookmark is stale"
                if let path = originalPath {
                    msg += " (original path: \(path))"
                }
                if let date = createdAt {
                    msg += " (created: \(date))"
                }
                return msg
            case .bookmarkResolutionFailed(let error):
                return "Bookmark resolution failed: \(error.localizedDescription)"
            case .securityScopeAccessDenied(let url):
                return "Security scope access denied for: \(url.path)"
            case .unsupportedLocatorType:
                return "Unsupported locator type"
            case .networkNotImplemented(let url):
                if let url = url {
                    return "Network access not implemented for: \(url.absoluteString)"
                }
                return "Network access not implemented"
            }
        }
    }

    /// Resolves this locator to a usable URL.
    ///
    /// - Returns: A `ResolvedURL` that must be released via `stopAccessing()` when done.
    /// - Throws: `ResolutionError` if resolution fails.
    ///
    /// ## Usage
    /// ```swift
    /// let resolved = try await locator.resolve()
    /// defer { resolved.stopAccessing() }
    /// // Use resolved.url
    /// ```
    public func resolve() async throws -> ResolvedURL {
        switch self {
        case .filePath(let path):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                throw ResolutionError.fileNotFound(path: path)
            }
            return ResolvedURL(url: url, isSecurityScoped: false)

        case .securityScopedBookmark(let data):
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    // Attempt to get original path from the resolved URL for debugging
                    throw ResolutionError.bookmarkStale(
                        originalPath: url.path,
                        createdAt: nil
                    )
                }

                guard url.startAccessingSecurityScopedResource() else {
                    throw ResolutionError.securityScopeAccessDenied(url: url)
                }

                return ResolvedURL(url: url, isSecurityScoped: true)
            } catch let error as ResolutionError {
                throw error
            } catch {
                throw ResolutionError.bookmarkResolutionFailed(underlyingError: error)
            }

        case .url(let url):
            if url.isFileURL {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ResolutionError.fileNotFound(path: url.path)
                }
            }
            return ResolvedURL(url: url, isSecurityScoped: false)

        case .http(let url, _):
            // Future: Implement remote URL handling
            throw ResolutionError.networkNotImplemented(url: url)

        case .s3(let bucket, let key, _):
            // Future: Implement S3 access
            let s3URL = URL(string: "s3://\(bucket)/\(key)")
            throw ResolutionError.networkNotImplemented(url: s3URL)
        }
    }
}

// MARK: - CustomStringConvertible

extension MediaLocator: CustomStringConvertible {
    public var description: String {
        switch self {
        case .filePath(let path):
            return "file:\(path)"
        case .securityScopedBookmark:
            return "bookmark:<data>"
        case .url(let url):
            return "url:\(url.absoluteString)"
        case .http(let url, let supportsRange):
            return "http:\(url.absoluteString) (range:\(supportsRange))"
        case .s3(let bucket, let key, let region):
            return "s3://\(bucket)/\(key) (\(region))"
        }
    }
}
