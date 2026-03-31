import Foundation

struct EvtxFileHeader {
    static let signature: [UInt8] = [0x45, 0x6C, 0x66, 0x46, 0x69, 0x6C, 0x65, 0x00] // "ElfFile\0"
    static let headerSize = 4096

    let firstChunkNumber: UInt64
    let lastChunkNumber: UInt64
    let nextRecordId: UInt64
    let minorVersion: UInt16
    let majorVersion: UInt16
    let headerBlockSize: UInt16
    let chunkCount: UInt16
}

struct EvtxChunkHeader {
    static let signature: [UInt8] = [0x45, 0x6C, 0x66, 0x43, 0x68, 0x6E, 0x6B, 0x00] // "ElfChnk\0"
    static let chunkSize = 65536
    static let headerSize = 512

    let firstEventRecordNumber: UInt64
    let lastEventRecordNumber: UInt64
    let firstEventRecordId: UInt64
    let lastEventRecordId: UInt64
    let freeSpaceOffset: UInt32
}

struct RawEventRecord {
    let recordId: UInt64
    let timestamp: Date
    let binXmlData: Data
}

// MARK: - EVTX Parser

class EvtxParser {
    enum ParseError: Error, LocalizedError {
        case invalidFile(String)
        case readError

        var errorDescription: String? {
            switch self {
            case .invalidFile(let msg): return "Invalid EVTX file: \(msg)"
            case .readError: return "Failed to read file"
            }
        }
    }

    private let data: Data

    init(data: Data) {
        self.data = data
    }

    convenience init(url: URL) throws {
        let data = try Data(contentsOf: url)
        self.init(data: data)
    }

    func parse(progress: ((Double) -> Void)? = nil) throws -> [EvtxEvent] {
        let header = try parseFileHeader()
        var events: [EvtxEvent] = []
        let totalChunks = max(Int(header.chunkCount), 1)

        var chunkIndex = 0
        var offset = EvtxFileHeader.headerSize

        while offset + EvtxChunkHeader.chunkSize <= data.count {
            if let chunkEvents = parseChunk(at: offset) {
                events.append(contentsOf: chunkEvents)
            }
            offset += EvtxChunkHeader.chunkSize
            chunkIndex += 1
            progress?(Double(chunkIndex) / Double(totalChunks))
        }

        return events.sorted { $0.recordId < $1.recordId }
    }

    // MARK: - File Header

    private func parseFileHeader() throws -> EvtxFileHeader {
        guard data.count >= EvtxFileHeader.headerSize else {
            throw ParseError.invalidFile("File too small")
        }

        let sig = [UInt8](data.prefix(8))
        guard sig == EvtxFileHeader.signature else {
            throw ParseError.invalidFile("Invalid signature")
        }

        return EvtxFileHeader(
            firstChunkNumber: data.readUInt64(at: 8),
            lastChunkNumber: data.readUInt64(at: 16),
            nextRecordId: data.readUInt64(at: 24),
            minorVersion: data.readUInt16(at: 32),
            majorVersion: data.readUInt16(at: 34),
            headerBlockSize: data.readUInt16(at: 36),
            chunkCount: data.readUInt16(at: 38)
        )
    }

    // MARK: - Chunk Parsing

    private func parseChunk(at chunkOffset: Int) -> [EvtxEvent]? {
        guard chunkOffset + EvtxChunkHeader.chunkSize <= data.count else { return nil }

        let chunkData = data.subdata(
            in: chunkOffset..<(chunkOffset + EvtxChunkHeader.chunkSize)
        )

        let sig = [UInt8](chunkData.prefix(8))
        guard sig == EvtxChunkHeader.signature else { return nil }

        let freeSpaceOffset = Int(chunkData.readUInt32(at: 40))
        let parser = BinXmlParser(chunkData: chunkData)

        var events: [EvtxEvent] = []
        var recordOffset = EvtxChunkHeader.headerSize

        while recordOffset < min(freeSpaceOffset, EvtxChunkHeader.chunkSize) {
            guard recordOffset + 24 <= EvtxChunkHeader.chunkSize else { break }

            let magic = chunkData.readUInt32(at: recordOffset)
            guard magic == 0x00002A2A else {
                recordOffset += 4
                continue
            }

            let recordSize = Int(chunkData.readUInt32(at: recordOffset + 4))
            guard recordSize >= 24, recordOffset + recordSize <= EvtxChunkHeader.chunkSize else {
                break
            }

            let recordId = chunkData.readUInt64(at: recordOffset + 8)
            let fileTime = chunkData.readUInt64(at: recordOffset + 16)
            let timestamp = fileTimeToDate(fileTime)

            let binXmlStart = recordOffset + 24
            let binXmlEnd = recordOffset + recordSize - 4 // last 4 bytes = copy of size
            if binXmlStart < binXmlEnd {
                let binXmlData = chunkData.safeSubdata(in: binXmlStart..<binXmlEnd)
                let xml = parser.parse(binXmlData: binXmlData)

                if !xml.isEmpty {
                    let event = EvtxEvent.fromXml(xml, recordId: recordId, timestamp: timestamp)
                    events.append(event)
                }
            }

            recordOffset += recordSize
        }

        return events
    }
}
