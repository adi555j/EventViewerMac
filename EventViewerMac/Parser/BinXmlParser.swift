import Foundation

// MARK: - BinXML Token Types
private enum BinXmlToken: UInt8 {
    case endOfStream = 0x00
    case openStartElement = 0x01
    case closeStartElement = 0x02
    case closeEmptyElement = 0x03
    case closeElement = 0x04
    case valueText = 0x05
    case attribute = 0x06
    case cdataSection = 0x07
    case entityRef = 0x09
    case templateInstance = 0x0C
    case normalSubstitution = 0x0D
    case optionalSubstitution = 0x0E
    case fragmentHeader = 0x0F
}

// MARK: - Value Types
enum BinXmlValueType: UInt8 {
    case null = 0x00
    case string = 0x01
    case ansiString = 0x02
    case int8 = 0x03
    case uint8 = 0x04
    case int16 = 0x05
    case uint16 = 0x06
    case int32 = 0x07
    case uint32 = 0x08
    case int64 = 0x09
    case uint64 = 0x0A
    case float32 = 0x0B
    case float64 = 0x0C
    case boolean = 0x0D
    case binary = 0x0E
    case guid = 0x0F
    case sizeT = 0x10
    case fileTime = 0x11
    case systemTime = 0x12
    case sid = 0x13
    case hexInt32 = 0x14
    case hexInt64 = 0x15
    case binXml = 0x21
    case stringArray = 0x81
}

private struct SubstitutionDescriptor {
    let size: UInt16
    let valueType: UInt8
}

// MARK: - BinXML Parser

class BinXmlParser {
    private let chunkData: Data
    private var templateCache: [Int: Data] = [:]
    private var templateChunkOffsets: [Int: Int] = [:]
    private var currentBase: Int = 0

    init(chunkData: Data) {
        self.chunkData = chunkData
    }

    func parse(binXmlData: Data, chunkOffset: Int) -> String {
        currentBase = chunkOffset
        var output = ""
        var pos = 0
        parseBinXml(data: binXmlData, pos: &pos, output: &output, substitutions: nil)
        return output
    }

    // MARK: - Inline Name Entry Handling

    /// BinXML embeds string table entries inline. After reading a name_offset,
    /// if the current chunk position matches the offset, skip past the entry.
    private func skipInlineNameIfNeeded(data: Data, pos: inout Int, nameOffset: Int) {
        let currentChunkPos = currentBase + pos
        guard currentChunkPos == nameOffset else { return }
        guard nameOffset + 8 <= chunkData.count else { return }
        let strLen = Int(chunkData.readUInt16(at: nameOffset + 6))
        // entry: next(4) + hash(2) + length(2) + data(strLen*2) + null(2)
        let entrySize = 4 + 2 + 2 + strLen * 2 + 2
        pos += entrySize
    }

    // MARK: - Core Parser

    private func parseBinXml(data: Data, pos: inout Int, output: inout String,
                             substitutions: [Data]?) {
        while pos < data.count {
            let rawToken = data.readUInt8(at: pos)
            let tokenValue = rawToken & 0x0F
            guard let token = BinXmlToken(rawValue: tokenValue) else {
                pos += 1
                continue
            }

            switch token {
            case .endOfStream:
                pos += 1
                return
            case .fragmentHeader:
                pos += 4
            case .openStartElement:
                parseOpenStartElement(data: data, pos: &pos, output: &output,
                                      hasAttributes: (rawToken & 0x40) != 0,
                                      substitutions: substitutions)
            case .closeStartElement:
                output += ">"
                pos += 1
            case .closeEmptyElement:
                output += "/>"
                pos += 1
            case .closeElement:
                pos += 1
            case .valueText:
                parseValueText(data: data, pos: &pos, output: &output)
            case .attribute:
                parseAttribute(data: data, pos: &pos, output: &output,
                               substitutions: substitutions)
            case .templateInstance:
                parseTemplateInstance(data: data, pos: &pos, output: &output)
            case .normalSubstitution, .optionalSubstitution:
                parseSubstitution(data: data, pos: &pos, output: &output,
                                  substitutions: substitutions)
            case .cdataSection:
                pos += 1
                let textLen = Int(data.readUInt16(at: pos))
                pos += 2
                output += data.readUTF16String(at: pos, byteCount: textLen)
                pos += textLen
            case .entityRef:
                pos += 1
                let nameOff = Int(data.readUInt32(at: pos))
                pos += 4
                output += "&\(readChunkString(at: nameOff));"
            }
        }
    }

    // MARK: - Element

    private func parseOpenStartElement(data: Data, pos: inout Int, output: inout String,
                                       hasAttributes: Bool, substitutions: [Data]?) {
        pos += 1 // token
        _ = data.readUInt16(at: pos) // dependency_id
        pos += 2
        _ = data.readUInt32(at: pos) // data_size
        pos += 4
        let nameOffset = Int(data.readUInt32(at: pos))
        pos += 4

        let elementName = readChunkString(at: nameOffset)
        output += "<\(elementName)"

        skipInlineNameIfNeeded(data: data, pos: &pos, nameOffset: nameOffset)

        if hasAttributes {
            _ = data.readUInt32(at: pos) // attribute_list_size
            pos += 4
            while pos < data.count {
                let nextByte = data.readUInt8(at: pos)
                let nextToken = nextByte & 0x0F
                if nextToken == BinXmlToken.attribute.rawValue {
                    parseAttribute(data: data, pos: &pos, output: &output,
                                   substitutions: substitutions)
                } else {
                    break
                }
            }
        }

        guard pos < data.count else { return }
        let peekByte = data.readUInt8(at: pos) & 0x0F
        if peekByte == BinXmlToken.closeEmptyElement.rawValue {
            output += "/>"
            pos += 1
        } else if peekByte == BinXmlToken.closeStartElement.rawValue {
            output += ">"
            pos += 1
            parseContent(data: data, pos: &pos, output: &output,
                         elementName: elementName, substitutions: substitutions)
        }
    }

    private func parseContent(data: Data, pos: inout Int, output: inout String,
                              elementName: String, substitutions: [Data]?) {
        while pos < data.count {
            let rawToken = data.readUInt8(at: pos)
            let tokenValue = rawToken & 0x0F

            if tokenValue == BinXmlToken.closeElement.rawValue {
                output += "</\(elementName)>"
                pos += 1
                return
            }
            if tokenValue == BinXmlToken.endOfStream.rawValue {
                output += "</\(elementName)>"
                pos += 1
                return
            }

            guard let token = BinXmlToken(rawValue: tokenValue) else {
                pos += 1
                continue
            }

            switch token {
            case .openStartElement:
                parseOpenStartElement(data: data, pos: &pos, output: &output,
                                      hasAttributes: (rawToken & 0x40) != 0,
                                      substitutions: substitutions)
            case .valueText:
                parseValueText(data: data, pos: &pos, output: &output)
            case .normalSubstitution, .optionalSubstitution:
                parseSubstitution(data: data, pos: &pos, output: &output,
                                  substitutions: substitutions)
            case .templateInstance:
                parseTemplateInstance(data: data, pos: &pos, output: &output)
            case .cdataSection:
                pos += 1
                let textLen = Int(data.readUInt16(at: pos))
                pos += 2
                output += data.readUTF16String(at: pos, byteCount: textLen)
                pos += textLen
            default:
                pos += 1
            }
        }
    }

    // MARK: - Attribute

    private func parseAttribute(data: Data, pos: inout Int, output: inout String,
                                substitutions: [Data]?) {
        pos += 1 // token
        let nameOffset = Int(data.readUInt32(at: pos))
        pos += 4

        let attrName = readChunkString(at: nameOffset)
        output += " \(attrName)=\""

        skipInlineNameIfNeeded(data: data, pos: &pos, nameOffset: nameOffset)

        guard pos < data.count else { output += "\""; return }
        let rawToken = data.readUInt8(at: pos)
        let tokenValue = rawToken & 0x0F
        if tokenValue == BinXmlToken.valueText.rawValue {
            parseValueText(data: data, pos: &pos, output: &output)
        } else if tokenValue == BinXmlToken.normalSubstitution.rawValue ||
                    tokenValue == BinXmlToken.optionalSubstitution.rawValue {
            parseSubstitution(data: data, pos: &pos, output: &output,
                              substitutions: substitutions)
        }
        output += "\""
    }

    // MARK: - Value

    private func parseValueText(data: Data, pos: inout Int, output: inout String) {
        pos += 1 // token
        let valueType = data.readUInt8(at: pos)
        pos += 1

        switch BinXmlValueType(rawValue: valueType) {
        case .string:
            let charLen = Int(data.readUInt16(at: pos))
            pos += 2
            let byteLen = charLen * 2
            output += xmlEscape(data.readUTF16String(at: pos, byteCount: byteLen))
            pos += byteLen
        case .uint16:
            output += "\(data.readUInt16(at: pos))"
            pos += 2
        case .uint32, .hexInt32:
            output += "\(data.readUInt32(at: pos))"
            pos += 4
        case .uint64, .hexInt64:
            output += "\(data.readUInt64(at: pos))"
            pos += 8
        case .int32:
            output += "\(Int32(bitPattern: data.readUInt32(at: pos)))"
            pos += 4
        case .fileTime:
            output += iso8601(fileTimeToDate(data.readUInt64(at: pos)))
            pos += 8
        case .guid:
            output += data.readGUID(at: pos)
            pos += 16
        case .boolean:
            output += data.readUInt32(at: pos) != 0 ? "true" : "false"
            pos += 4
        default:
            break
        }
    }

    // MARK: - Substitution

    private func parseSubstitution(data: Data, pos: inout Int, output: inout String,
                                   substitutions: [Data]?) {
        pos += 1
        let subId = Int(data.readUInt16(at: pos))
        pos += 2
        let valueType = data.readUInt8(at: pos)
        pos += 1
        guard let subs = substitutions, subId < subs.count else { return }
        let subData = subs[subId]
        guard !subData.isEmpty else { return }
        formatValue(data: subData, type: valueType, output: &output)
    }

    // MARK: - Template Instance

    private func parseTemplateInstance(data: Data, pos: inout Int, output: inout String) {
        pos += 1 // 0x0C
        _ = data.readUInt8(at: pos) // unknown
        pos += 1
        _ = data.readUInt32(at: pos) // template ID hash
        pos += 4
        let templateDefOffset = Int(data.readUInt32(at: pos))
        pos += 4

        let templateBody: Data
        let templateDefTotalSize: Int
        let templateBodyChunkOffset: Int

        if templateDefOffset + 24 <= chunkData.count {
            let dataSize = Int(chunkData.readUInt32(at: templateDefOffset + 20))
            templateDefTotalSize = 24 + dataSize
            templateBodyChunkOffset = templateDefOffset + 24

            if let cached = templateCache[templateDefOffset] {
                templateBody = cached
            } else {
                if dataSize > 0 && templateDefOffset + templateDefTotalSize <= chunkData.count {
                    templateBody = chunkData.safeSubdata(
                        in: templateBodyChunkOffset..<(templateBodyChunkOffset + dataSize))
                } else {
                    templateBody = Data()
                }
                templateCache[templateDefOffset] = templateBody
            }
        } else {
            templateBody = Data()
            templateDefTotalSize = 0
            templateBodyChunkOffset = 0
        }

        // Skip inline template definition if present
        let currentChunkOffset = currentBase + pos
        if currentChunkOffset == templateDefOffset && templateDefTotalSize > 0 {
            pos += templateDefTotalSize
        }

        guard pos + 4 <= data.count else { return }
        let numValues = Int(data.readUInt32(at: pos))
        pos += 4
        guard numValues >= 0, numValues < 500 else { return }

        var descriptors: [SubstitutionDescriptor] = []
        for _ in 0..<numValues {
            guard pos + 4 <= data.count else { break }
            let size = data.readUInt16(at: pos); pos += 2
            let type = data.readUInt8(at: pos); pos += 1
            _ = data.readUInt8(at: pos); pos += 1 // padding
            descriptors.append(SubstitutionDescriptor(size: size, valueType: type))
        }

        var substitutions: [Data] = []
        for desc in descriptors {
            let size = Int(desc.size)
            if size > 0 && pos + size <= data.count {
                substitutions.append(data.safeSubdata(in: pos..<(pos + size)))
                pos += size
            } else {
                substitutions.append(Data())
                if size > 0 { pos = Swift.min(pos + size, data.count) }
            }
        }

        let savedBase = currentBase
        currentBase = templateBodyChunkOffset
        var tPos = 0
        parseBinXml(data: templateBody, pos: &tPos, output: &output, substitutions: substitutions)
        currentBase = savedBase
    }

    // MARK: - Value Formatting

    private func formatValue(data: Data, type: UInt8, output: inout String) {
        switch BinXmlValueType(rawValue: type) {
        case .null: break
        case .string:
            let str = String(data: data, encoding: .utf16LittleEndian)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
            output += xmlEscape(str)
        case .ansiString:
            let str = String(data: data, encoding: .ascii)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
            output += xmlEscape(str)
        case .int8:  output += "\(Int8(bitPattern: data.readUInt8(at: 0)))"
        case .uint8: output += "\(data.readUInt8(at: 0))"
        case .int16: output += "\(Int16(bitPattern: data.readUInt16(at: 0)))"
        case .uint16: output += "\(data.readUInt16(at: 0))"
        case .int32: output += "\(Int32(bitPattern: data.readUInt32(at: 0)))"
        case .uint32: output += "\(data.readUInt32(at: 0))"
        case .int64: output += "\(data.readInt64(at: 0))"
        case .uint64: output += "\(data.readUInt64(at: 0))"
        case .float32:
            var v: Float = 0
            _ = withUnsafeMutableBytes(of: &v) { p in
                for i in 0..<Swift.min(4, data.count) { p[i] = data[data.startIndex + i] }
            }
            output += "\(v)"
        case .float64:
            var v: Double = 0
            _ = withUnsafeMutableBytes(of: &v) { p in
                for i in 0..<Swift.min(8, data.count) { p[i] = data[data.startIndex + i] }
            }
            output += "\(v)"
        case .boolean:
            output += data.readUInt32(at: 0) != 0 ? "true" : "false"
        case .binary:
            output += data.map { String(format: "%02X", $0) }.joined()
        case .guid:
            output += data.readGUID(at: 0)
        case .sizeT:
            output += "\(data.readUInt64(at: 0))"
        case .fileTime:
            output += iso8601(fileTimeToDate(data.readUInt64(at: 0)))
        case .systemTime:
            guard data.count >= 16 else { break }
            let y = data.readUInt16(at: 0), mo = data.readUInt16(at: 2)
            let d = data.readUInt16(at: 6), h = data.readUInt16(at: 8)
            let mi = data.readUInt16(at: 10), s = data.readUInt16(at: 12)
            let ms = data.readUInt16(at: 14)
            output += String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", y, mo, d, h, mi, s, ms)
        case .sid:
            output += data.readSID(at: 0, length: data.count)
        case .hexInt32:
            output += String(format: "0x%08X", data.readUInt32(at: 0))
        case .hexInt64:
            output += String(format: "0x%016llX", data.readUInt64(at: 0))
        case .binXml:
            var subPos = 0
            parseBinXml(data: data, pos: &subPos, output: &output, substitutions: nil)
        case .stringArray:
            var sp = 0
            var parts: [String] = []
            while sp + 1 < data.count {
                let slice = data.safeSubdata(in: sp..<data.count)
                if let r = slice.range(of: Data([0x00, 0x00])) {
                    let n = slice.distance(from: slice.startIndex, to: r.lowerBound)
                    guard n >= 0 else { break }
                    if n > 0 {
                        parts.append(String(data: slice.safeSubdata(in: 0..<n),
                                            encoding: .utf16LittleEndian) ?? "")
                    }
                    sp += n + 2
                } else {
                    let s = String(data: slice, encoding: .utf16LittleEndian) ?? ""
                    if !s.isEmpty { parts.append(s) }
                    break
                }
            }
            output += xmlEscape(parts.joined(separator: ", "))
        case .none:
            output += data.map { String(format: "%02X", $0) }.joined()
        }
    }

    // MARK: - String Table

    func readChunkString(at offset: Int) -> String {
        guard offset >= 0, offset + 8 < chunkData.count else { return "?" }
        let length = Int(chunkData.readUInt16(at: offset + 6))
        guard length > 0, offset + 8 + length * 2 <= chunkData.count else { return "?" }
        return chunkData.readUTF16String(at: offset + 8, byteCount: length * 2)
    }

    // MARK: - Helpers

    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func iso8601(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}
