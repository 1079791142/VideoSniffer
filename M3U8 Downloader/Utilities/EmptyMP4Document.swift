import SwiftUI
import UniformTypeIdentifiers

struct EmptyMP4Document: FileDocument {
    static var readableContentTypes: [UTType] { [.mpeg4Movie] }
    static var writableContentTypes: [UTType] { [.mpeg4Movie] }

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}
