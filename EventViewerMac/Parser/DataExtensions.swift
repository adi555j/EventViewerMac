import Foundation

extension Data {
    func readUInt8(at offset: Int) -> UInt8 {
        guard offset < count else { return 0 }
        return self[startIndex + offset]
    }

    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }

    func readUInt64(at offset: Int) -> UInt64 {
        guard offset + 7 < count else { return 0 }
        let base = startIndex + offset
        var result: UInt64 = 0
        for i in 0..<8 {
            result |= UInt64(self[base + i]) << (i * 8)
        }
        return result
    }

    func readInt64(at offset: Int) -> Int64 {
        Int64(bitPattern: readUInt64(at: offset))
    }

    func readUTF16String(at offset: Int, byteCount: Int) -> String {
        guard offset + byteCount <= count, byteCount > 0 else { return "" }
        let sub = subdata(in: (startIndex + offset)..<(startIndex + offset + byteCount))
        return String(data: sub, encoding: .utf16LittleEndian) ?? ""
    }

    func readGUID(at offset: Int) -> String {
        guard offset + 16 <= count else { return "" }
        let d1 = readUInt32(at: offset)
        let d2 = readUInt16(at: offset + 4)
        let d3 = readUInt16(at: offset + 6)
        let base = startIndex + offset
        return String(
            format: "{%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}",
            d1, d2, d3,
            self[base + 8], self[base + 9],
            self[base + 10], self[base + 11], self[base + 12],
            self[base + 13], self[base + 14], self[base + 15]
        )
    }

    func readSID(at offset: Int, length: Int) -> String {
        guard offset + length <= count, length >= 8 else { return "" }
        let base = startIndex + offset
        let revision = self[base]
        let subAuthorityCount = Int(self[base + 1])
        let authority: UInt64 = (0..<6).reduce(0) { acc, i in
            acc | (UInt64(self[base + 2 + i]) << ((5 - i) * 8))
        }
        var result = "S-\(revision)-\(authority)"
        for i in 0..<subAuthorityCount {
            let subOff = offset + 8 + i * 4
            guard subOff + 4 <= offset + length else { break }
            result += "-\(readUInt32(at: subOff))"
        }
        return result
    }

    func safeSubdata(in range: Range<Int>) -> Data {
        let clampedLower = Swift.max(range.lowerBound, 0)
        let clampedUpper = Swift.min(range.upperBound, count)
        guard clampedLower < clampedUpper else { return Data() }
        return subdata(in: (startIndex + clampedLower)..<(startIndex + clampedUpper))
    }
}

func fileTimeToDate(_ filetime: UInt64) -> Date {
    let unixSeconds = Double(filetime) / 10_000_000.0 - 11_644_473_600.0
    return Date(timeIntervalSince1970: unixSeconds)
}
