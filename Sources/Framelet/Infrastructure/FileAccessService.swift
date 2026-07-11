import Foundation

struct FileAccessService: Sendable {
    struct ResolvedAccess: @unchecked Sendable {
        let url: URL
        private let isSecurityScoped: Bool

        init(url: URL, isSecurityScoped: Bool) {
            self.url = url
            self.isSecurityScoped = isSecurityScoped
        }

        func stopAccessing() {
            if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        }
    }

    func resolve(_ reference: MediaReference) throws -> ResolvedAccess {
        if let bookmark = reference.bookmarkData {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if !isStale, FileManager.default.fileExists(atPath: url.path) {
                    return ResolvedAccess(url: url, isSecurityScoped: url.startAccessingSecurityScopedResource())
                }
            } catch {
                // Fall back to the recorded path for projects created before sandboxing.
            }
        }

        let fallback = URL(fileURLWithPath: reference.originalPath)
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return ResolvedAccess(url: fallback, isSecurityScoped: fallback.startAccessingSecurityScopedResource())
    }

    func makeReference(for url: URL) throws -> MediaReference {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return MediaReference(
            originalPath: url.path,
            bookmarkData: bookmark,
            fileSize: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? Date()
        )
    }
}
