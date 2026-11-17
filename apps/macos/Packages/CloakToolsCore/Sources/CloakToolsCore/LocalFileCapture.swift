import Foundation

enum LocalFileCapture {
    static func read(_ url: URL, limit: Int) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnknown) }
        guard (values.fileSize ?? Int.max) <= limit else { throw CaptureError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = Data()
        while let chunk = try handle.read(upToCount: min(65_536, limit + 1 - bytes.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            bytes.append(chunk)
            guard bytes.count <= limit else { throw CaptureError.tooLarge }
        }
        return bytes
    }
    enum CaptureError: Error { case tooLarge }
}
