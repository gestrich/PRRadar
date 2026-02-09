import Foundation

public struct ImageDownloadService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - URL Resolution

    /// Parses the raw markdown body for `github.com/user-attachments/assets/` image URLs,
    /// finds corresponding resolved signed URLs in the rendered `bodyHTML`, and returns a mapping.
    public func resolveImageURLs(body: String, bodyHTML: String) -> [String: URL] {
        let originalURLs = extractUserAttachmentURLs(from: body)
        guard !originalURLs.isEmpty else { return [:] }

        let resolvedSrcURLs = extractImgSrcURLs(from: bodyHTML)

        var mapping: [String: URL] = [:]
        for originalURL in originalURLs {
            guard let uuid = extractUUID(from: originalURL) else { continue }
            for srcURL in resolvedSrcURLs {
                if srcURL.contains(uuid), let resolved = URL(string: srcURL) {
                    mapping[originalURL] = resolved
                    break
                }
            }
        }
        return mapping
    }

    // MARK: - Download

    /// Downloads each image from its signed URL, saves with a deterministic filename
    /// (UUID from the original URL + detected extension), returns mapping of originalURL → localFilename.
    public func downloadImages(
        urls: [String: URL],
        to directory: String
    ) async throws -> [String: String] {
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )

        var urlMap: [String: String] = [:]
        for (originalURL, signedURL) in urls {
            guard let uuid = extractUUID(from: originalURL) else { continue }
            do {
                let (data, response) = try await session.data(from: signedURL)
                let ext = fileExtension(from: response, data: data)
                let filename = "\(uuid).\(ext)"
                let filePath = "\(directory)/\(filename)"
                try data.write(to: URL(fileURLWithPath: filePath))
                urlMap[originalURL] = filename
            } catch {
                // Image download failures are non-fatal — the original URL stays in place
                continue
            }
        }
        return urlMap
    }

    // MARK: - Body Rewrite

    /// Replaces original GitHub user-attachment URLs in the body text with local file paths.
    public func rewriteBody(
        _ body: String,
        urlMap: [String: String],
        baseDir: String
    ) -> String {
        var result = body
        for (originalURL, localFilename) in urlMap {
            result = result.replacingOccurrences(of: originalURL, with: "\(baseDir)/\(localFilename)")
        }
        return result
    }

    // MARK: - Private

    private static let userAttachmentPattern = #"https://github\.com/user-attachments/assets/[0-9a-fA-F\-]+"#

    private func extractUserAttachmentURLs(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: Self.userAttachmentPattern) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var urls: [String] = []
        for match in matches {
            if let matchRange = Range(match.range, in: text) {
                let url = String(text[matchRange])
                if !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private func extractImgSrcURLs(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<img[^>]+src="([^"]+)""#) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        var urls: [String] = []
        for match in matches {
            if match.numberOfRanges >= 2,
               let srcRange = Range(match.range(at: 1), in: html) {
                urls.append(String(html[srcRange]))
            }
        }
        return urls
    }

    private static let uuidPattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#

    private func extractUUID(from urlString: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: Self.uuidPattern) else {
            return nil
        }
        let range = NSRange(urlString.startIndex..., in: urlString)
        guard let match = regex.firstMatch(in: urlString, range: range),
              let matchRange = Range(match.range, in: urlString) else {
            return nil
        }
        return String(urlString[matchRange]).lowercased()
    }

    private func fileExtension(from response: URLResponse, data: Data) -> String {
        if let mimeType = response.mimeType {
            switch mimeType {
            case "image/png": return "png"
            case "image/jpeg": return "jpg"
            case "image/gif": return "gif"
            case "image/webp": return "webp"
            case "image/svg+xml": return "svg"
            default: break
            }
        }

        // Fall back to magic bytes
        if data.count >= 8 {
            let bytes = [UInt8](data.prefix(8))
            if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
            if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
            if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
            if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && Array(bytes[4...7]) == [0x57, 0x45, 0x42, 0x50] {
                return "webp"
            }
        }

        return "png"
    }
}
