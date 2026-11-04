import Compression
import Foundation

/// A minimal read-only ZIP reader: just enough for EPUB (stored and deflated entries, no ZIP64).
///
/// The app reads the whole archive into memory rather than memory-mapping it, so that rewriting
/// the file while it is open (e.g. rebuilding the EPUB) can't crash it. The Quick Look extensions
/// map it instead: they live for a moment, and shouldn't read a 100 MB book to draw a cover.
final class ZipArchive {
    struct Entry {
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    enum ZipError: LocalizedError {
        case notZip, unsupported, corrupt

        var errorDescription: String? {
            switch self {
            case .notZip: String(localized: "The file isn't a ZIP archive.")
            case .unsupported: String(localized: "The file uses a ZIP feature Quire doesn't support.")
            case .corrupt: String(localized: "The file is damaged.")
            }
        }
    }

    /// Upper bound on one entry's declared size, so a broken header can't make us allocate gigabytes.
    private static let maxEntrySize = 512 << 20

    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    init(url: URL, mapped: Bool = false) throws {
        data = try Data(contentsOf: url, options: mapped ? .alwaysMapped : [])
        try readCentralDirectory()
    }

    func contains(_ path: String) -> Bool { entries[path] != nil }

    func read(_ path: String) throws -> Data {
        guard let entry = entries[path] else { throw CocoaError(.fileReadNoSuchFile) }
        guard u32(entry.localHeaderOffset) == 0x0403_4b50 else { throw ZipError.corrupt }
        let start = entry.localHeaderOffset + 30 + Int(u16(entry.localHeaderOffset + 26)) + Int(u16(entry.localHeaderOffset + 28))
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt }
        let range = data.startIndex + start ..< data.startIndex + start + entry.compressedSize

        switch entry.method {
        case 0:
            return data.subdata(in: range)
        case 8:
            if entry.size == 0 { return Data() }
            guard entry.compressedSize > 0 else { throw ZipError.corrupt }
            var out = Data(count: entry.size)
            let written = out.withUnsafeMutableBytes { dst in
                data[range].withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, entry.size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, entry.compressedSize,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.size else { throw ZipError.corrupt }
            return out
        default:
            throw ZipError.unsupported
        }
    }

    private func readCentralDirectory() throws {
        // The end-of-central-directory record is in the last 22 + 65535 (max comment) bytes.
        guard data.count >= 22 else { throw ZipError.notZip }
        var eocd = data.count - 22
        let lowest = max(0, data.count - 22 - 0xFFFF)
        while u32(eocd) != 0x0605_4b50 {
            guard eocd > lowest else { throw ZipError.notZip }
            eocd -= 1
        }
        let count = Int(u16(eocd + 10))
        let offset = Int(u32(eocd + 16))
        if count == 0xFFFF || offset == 0xFFFF_FFFF { throw ZipError.unsupported }

        var p = offset
        for _ in 0..<count {
            guard p + 46 <= data.count, u32(p) == 0x0201_4b50 else { throw ZipError.corrupt }
            let flags = u16(p + 8)
            let compressed = Int(u32(p + 20)), size = Int(u32(p + 24))
            let nameLength = Int(u16(p + 28)), extraLength = Int(u16(p + 30)), commentLength = Int(u16(p + 32))
            let local = Int(u32(p + 42))
            guard p + 46 + nameLength <= data.count else { throw ZipError.corrupt }
            if compressed == 0xFFFF_FFFF || size == 0xFFFF_FFFF || local == 0xFFFF_FFFF { throw ZipError.unsupported }
            if flags & 1 != 0 || size > Self.maxEntrySize { throw ZipError.unsupported }

            let nameBytes = data[data.startIndex + p + 46 ..< data.startIndex + p + 46 + nameLength]
            // EPUB requires UTF-8 names; fall back to Latin-1 rather than dropping the entry.
            let name = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1)!
            entries[name] = Entry(method: u16(p + 10), compressedSize: compressed, size: size, localHeaderOffset: local)
            p += 46 + nameLength + extraLength + commentLength
        }
    }

    private func u16(_ i: Int) -> UInt16 {
        guard i >= 0, i + 2 <= data.count else { return 0 }
        let b = data.startIndex + i
        return UInt16(data[b]) | UInt16(data[b + 1]) << 8
    }

    private func u32(_ i: Int) -> UInt32 {
        guard i >= 0, i + 4 <= data.count else { return 0 }
        return UInt32(u16(i)) | UInt32(u16(i + 2)) << 16
    }
}
