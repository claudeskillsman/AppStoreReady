import Foundation

/// Reads dimensions and alpha information from a PNG file's chunks without decoding pixels.
enum PNGReader {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func read(_ url: URL) -> PNGInfo? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        // Header chunks precede image data; 64 KB is more than enough.
        let data = handle.readData(ofLength: 65_536)
        return parse(data)
    }

    static func parse(_ data: Data) -> PNGInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 33, Array(bytes[0..<8]) == signature else { return nil }
        func uint32(_ offset: Int) -> Int {
            Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        guard String(decoding: bytes[12..<16], as: UTF8.self) == "IHDR" else { return nil }
        let width = uint32(16)
        let height = uint32(20)
        let colorType = bytes[25]
        var hasAlpha = colorType == 4 || colorType == 6
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = uint32(offset)
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if type == "tRNS" { hasAlpha = true }
            if type == "IDAT" || type == "IEND" { break }
            offset += 12 + length
        }
        return PNGInfo(width: width, height: height, hasAlpha: hasAlpha)
    }
}
