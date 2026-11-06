import Foundation

#if os(macOS)
func withSecurityScopedAccess<T>(bookmarkData: Data?, operation: () -> T) -> T {
    guard let bookmarkData else {
        return operation()
    }

    var isStale = false
    guard let url = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    ) else {
        return operation()
    }

    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
        if didAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
    return operation()
}
#endif
