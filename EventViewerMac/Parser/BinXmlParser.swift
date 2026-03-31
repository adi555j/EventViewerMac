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

// MARK: - Substitution Descriptor
private struct SubstitutionDescriptor {
    let size: UInt16
    let valueType: UInt8
}

// MARK: - BinXML Parser
class BinXmlParser {
    private let chunkData: Data
    private var templateCache: [UInt32: Data] = [:]

    init(chunkData: Data) {
        self.chunkData = chunkData
    }

    /// Parse the BinXML data starting from the given offset within the event record.
    /// `binXmlData` is the raw BinXML portion of the event record.
    func parse(binXmlData: Data) -> String {
        var output = ""
        var pos = 0
        parseBinXml(data: binXmlData, pos: &pos, output: &output, substitutions: nil)
        return output
    }

    // MARK: - Core Recursive Parser

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
                continue

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
                               hasMore: (rawToken & 0x40) != 0,
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
                let text = data.readUTF16String(at: pos, byteCount: textLen)
                output += "<![CDATA[\(text)]]>"
                pos += textLen

            case .entityRef:
                pos += 1
                let nameOffset = Int(data.readUInt32(at: pos))
                pos += 4
                let name = readChunkString(at: nameOffset)
                output += "&\(name);"
            }
        }
    }

    // MARK: - Element Parsing

    private func parseOpenStartElement(data: Data, pos: inout Int, output: inout String,
                                       hasAttributes: Bool, substitutions: [Data]?) {
        pos += 1 // token
        _ = data.readUInt16(at: pos) // dependency id
        pos += 2
        let dataSize = data.readUInt32(at: pos)
        pos += 4

        let nameOffset = Int(data.readUInt32(at: pos))
        pos += 4

        let elementName = readChunkString(at: nameOffset)
        output += "<\(elementName)"

        let endPos = pos + Int(dataSize) - 10

        if hasAttributes {
            _ = data.readUInt32(at: pos) // attribute list size
            pos += 4

            while pos < min(endPos, data.count) {
                let nextByte = data.readUInt8(at: pos)
                let nextToken = nextByte & 0x0F
                if nextToken == BinXmlToken.attribute.rawValue {
                    parseAttribute(data: data, pos: &pos, output: &output,
                                   hasMore: (nextByte & 0x40) != 0,
                                   substitutions: substitutions)
                } else {
                    break
                }
            }
        }

        let peekByte = pos < data.count ? data.readUInt8(at: pos) & 0x0F : 0
        if peekByte == BinXmlToken.closeEmptyElement.rawValue {
            output += "/>"
            pos += 1
        } else if peekByte == BinXmlToken.closeStartElement.rawValue {
            output += ">"
            pos += 1

            parseElementContent(data: data, pos: &pos, output: &output,
                                elementName: elementName, substitutions: substitutions)
        }
    }

    private func parseElementContent(data: Data, pos: inout Int, output: inout String,
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
                let text = data.readUTF16String(at: pos, byteCount: textLen)
                output += "<![CDATA[\(text)]]>"
                pos += textLen
            default:
                pos += 1
            }
        }
    }

    // MARK: - Attribute Parsing

    private func parseAttribute(data: Data, pos: inout Int, output: inout String,
                                hasMore: Bool, substitutions: [Data]?) {
        pos += 1 // token
        let nameOffset = Int(data.readUInt32(at: pos))
        pos += 4

        let attrName = readChunkString(at: nameOffset)
        output += " \(attrName)=\""

        parseAttributeValue(data: data, pos: &pos, output: &output,
                            substitutions: substitutions)

        output += "\""
    }

    private func parseAttributeValue(data: Data, pos: inout Int, output: inout String,
                                     substitutions: [Data]?) {
        guard pos < data.count else { return }
        let rawToken = data.readUInt8(at: pos)
        let tokenValue = rawToken & 0x0F

        if tokenValue == BinXmlToken.valueText.rawValue {
            parseValueText(data: data, pos: &pos, output: &output)
        } else if tokenValue == BinXmlToken.normalSubstitution.rawValue ||
                    tokenValue == BinXmlToken.optionalSubstitution.rawValue {
            parseSubstitution(data: data, pos: &pos, output: &output,
                              substitutions: substitutions)
        } else {
            // Unexpected token in attribute value
        }
    }

    // MARK: - Value Parsing

    private func parseValueText(data: Data, pos: inout Int, output: inout String) {
        pos += 1 // token
        let valueType = data.readUInt8(at: pos)
        pos += 1

        switch BinXmlValueType(rawValue: valueType) {
        case .string:
            let byteLen = Int(data.readUInt16(at: pos))
            pos += 2
            let str = data.readUTF16String(at: pos, byteCount: byteLen)
            output += xmlEscape(str)
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
            let ft = data.readUInt64(at: pos)
            let date = fileTimeToDate(ft)
            output += iso8601String(from: date)
            pos += 8
        case .guid:
            output += data.readGUID(at: pos)
            pos += 16
        case .boolean:
            let val = data.readUInt32(at: pos)
            output += val != 0 ? "true" : "false"
            pos += 4
        default:
            break
        }
    }

    // MARK: - Substitution

    private func parseSubstitution(data: Data, pos: inout Int, output: inout String,
                                   substitutions: [Data]?) {
        pos += 1 // token
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
        pos += 1 // token (0x0C)
        _ = data.readUInt8(at: pos) // unknown byte
        pos += 1
        let templateDefOffset = data.readUInt32(at: pos)
        pos += 4
        _ = data.readUInt32(at: pos) // next template data offset
        pos += 4

        let templateBody: Data
        if let cached = templateCache[templateDefOffset] {
            templateBody = cached
        } else {
            templateBody = readTemplateDefinition(at: Int(templateDefOffset))
            templateCache[templateDefOffset] = templateBody
        }

        let numValues = Int(data.readUInt32(at: pos))
        pos += 4

        var descriptors: [SubstitutionDescriptor] = []
        for _ in 0..<numValues {
            let size = data.readUInt16(at: pos)
            pos += 2
            let type = data.readUInt8(at: pos)
            pos += 1
            _ = data.readUInt8(at: pos) // padding
            pos += 1
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
                if size > 0 { pos += size }
            }
        }

        var templatePos = 0
        parseTemplateBody(templateData: templateBody, pos: &templatePos,
                          output: &output, substitutions: substitutions)
    }

    private func readTemplateDefinition(at offset: Int) -> Data {
        guard offset + 24 <= chunkData.count else { return Data() }
        // Template definition header in chunk:
        // +0: next_template_offset (uint32)
        // +4: template_guid (16 bytes)
        // +20: data_size (uint32)
        // +24: fragment data
        let dataSize = Int(chunkData.readUInt32(at: offset + 20))
        guard dataSize > 0, offset + 24 + dataSize <= chunkData.count else { return Data() }
        return chunkData.safeSubdata(in: (offset + 24)..<(offset + 24 + dataSize))
    }

    private func parseTemplateBody(templateData: Data, pos: inout Int,
                                   output: inout String, substitutions: [Data]) {
        while pos < templateData.count {
            let rawToken = templateData.readUInt8(at: pos)
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
                continue

            case .openStartElement:
                parseOpenStartElement(data: templateData, pos: &pos, output: &output,
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
                parseValueText(data: templateData, pos: &pos, output: &output)

            case .attribute:
                parseAttribute(data: templateData, pos: &pos, output: &output,
                               hasMore: (rawToken & 0x40) != 0,
                               substitutions: substitutions)

            case .normalSubstitution, .optionalSubstitution:
                parseSubstitution(data: templateData, pos: &pos, output: &output,
                                  substitutions: substitutions)

            case .templateInstance:
                parseTemplateInstance(data: templateData, pos: &pos, output: &output)

            case .cdataSection, .entityRef:
                pos += 1
            }
        }
    }

    // MARK: - Value Formatting

    private func formatValue(data: Data, type: UInt8, output: inout String) {
        switch BinXmlValueType(rawValue: type) {
        case .null:
            break
        case .string:
            let str = String(data: data, encoding: .utf16LittleEndian)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
            output += xmlEscape(str)
        case .ansiString:
            let str = String(data: data, encoding: .ascii)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
            output += xmlEscape(str)
        case .int8:
            output += "\(Int8(bitPattern: data.readUInt8(at: 0)))"
        case .uint8:
            output += "\(data.readUInt8(at: 0))"
        case .int16:
            output += "\(Int16(bitPattern: data.readUInt16(at: 0)))"
        case .uint16:
            output += "\(data.readUInt16(at: 0))"
        case .int32:
            output += "\(Int32(bitPattern: data.readUInt32(at: 0)))"
        case .uint32:
            output += "\(data.readUInt32(at: 0))"
        case .int64:
            output += "\(data.readInt64(at: 0))"
        case .uint64:
            output += "\(data.readUInt64(at: 0))"
        case .float32:
            var val: Float = 0
            withUnsafeMutableBytes(of: &val) { ptr in
                for i in 0..<min(4, data.count) { ptr[i] = data[data.startIndex + i] }
            }
            output += "\(val)"
        case .float64:
            var val: Double = 0
            withUnsafeMutableBytes(of: &val) { ptr in
                for i in 0..<min(8, data.count) { ptr[i] = data[data.startIndex + i] }
            }
            output += "\(val)"
        case .boolean:
            output += data.readUInt32(at: 0) != 0 ? "true" : "false"
        case .binary:
            output += data.map { String(format: "%02X", $0) }.joined()
        case .guid:
            output += data.readGUID(at: 0)
        case .sizeT:
            output += "\(data.readUInt64(at: 0))"
        case .fileTime:
            let ft = data.readUInt64(at: 0)
            output += iso8601String(from: fileTimeToDate(ft))
        case .systemTime:
            if data.count >= 16 {
                let year = data.readUInt16(at: 0)
                let month = data.readUInt16(at: 2)
                let day = data.readUInt16(at: 6)
                let hour = data.readUInt16(at: 8)
                let minute = data.readUInt16(at: 10)
                let second = data.readUInt16(at: 12)
                let ms = data.readUInt16(at: 14)
                output += String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
                                 year, month, day, hour, minute, second, ms)
            }
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
            var strPos = 0
            var parts: [String] = []
            while strPos < data.count {
                let remaining = data.safeSubdata(in: strPos..<data.count)
                if let nullRange = remaining.range(of: Data([0x00, 0x00])) {
                    let strLen = remaining.distance(from: remaining.startIndex, to: nullRange.lowerBound)
                    let s = remaining.safeSubdata(in: 0..<strLen)
                    parts.append(String(data: s, encoding: .utf16LittleEndian) ?? "")
                    strPos += strLen + 2
                } else {
                    let s = String(data: remaining, encoding: .utf16LittleEndian) ?? ""
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
        // String entry: next_offset(4) + hash(2) + length(2) + UTF16LE data
        let length = Int(chunkData.readUInt16(at: offset + 6))
        guard length > 0, offset + 8 + length * 2 <= chunkData.count else { return "?" }
        return chunkData.readUTF16String(at: offset + 8, byteCount: length * 2)
    }

    // MARK: - Helpers

    private func xmlEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
           .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
