import Foundation

struct FileAccessService: Sendable {
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
