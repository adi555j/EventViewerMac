import Foundation

struct EvtxEvent: Identifiable, Hashable {
    let id: UInt64
    let recordId: UInt64
    let timestamp: Date
    let providerName: String
    let providerGuid: String
    let eventId: Int
    let version: Int
    let level: Int
    let task: Int
    let opcode: Int
    let keywords: String
    let channel: String
    let computer: String
    let userSID: String
    let processId: UInt32
    let threadId: UInt32
    let message: String
    let xmlContent: String

    var levelName: String {
        switch level {
        case 0: return "Info"
        case 1: return "Critical"
        case 2: return "Error"
        case 3: return "Warning"
        case 4: return "Info"
        case 5: return "Verbose"
        default: return "Level \(level)"
        }
    }

    var levelSymbol: String {
        switch level {
        case 1: return "xmark.octagon.fill"
        case 2: return "exclamationmark.circle.fill"
        case 3: return "exclamationmark.triangle.fill"
        case 4: return "info.circle.fill"
        case 5: return "text.alignleft"
        default: return "info.circle"
        }
    }

    static func fromXml(_ xml: String, recordId: UInt64, timestamp: Date) -> EvtxEvent {
        let parser = EventXmlParser(xml: xml)
        let fields = parser.parse()

        return EvtxEvent(
            id: recordId,
            recordId: recordId,
            timestamp: timestamp,
            providerName: fields["ProviderName"] ?? "",
            providerGuid: fields["ProviderGuid"] ?? "",
            eventId: Int(fields["EventID"] ?? "") ?? 0,
            version: Int(fields["Version"] ?? "") ?? 0,
            level: Int(fields["Level"] ?? "") ?? 4,
            task: Int(fields["Task"] ?? "") ?? 0,
            opcode: Int(fields["Opcode"] ?? "") ?? 0,
            keywords: fields["Keywords"] ?? "",
            channel: fields["Channel"] ?? "",
            computer: fields["Computer"] ?? "",
            userSID: fields["Security"] ?? "",
            processId: UInt32(fields["ProcessID"] ?? "") ?? 0,
            threadId: UInt32(fields["ThreadID"] ?? "") ?? 0,
            message: fields["EventData"] ?? fields["UserData"] ?? "",
            xmlContent: xml
        )
    }
}

private class EventXmlParser: NSObject, XMLParserDelegate {
    private let xml: String
    private var fields: [String: String] = [:]
    private var currentElement = ""
    private var currentText = ""
    private var inSystem = false
    private var inEventData = false
    private var inUserData = false
    private var eventDataParts: [String] = []
    private var currentDataName = ""

    init(xml: String) {
        self.xml = xml
    }

    func parse() -> [String: String] {
        guard let data = xml.data(using: .utf8) else { return fields }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return fields
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "System": inSystem = true
        case "EventData": inEventData = true
        case "UserData": inUserData = true
        case "Provider" where inSystem:
            fields["ProviderName"] = attributes["Name"] ?? ""
            fields["ProviderGuid"] = attributes["Guid"] ?? ""
        case "TimeCreated" where inSystem:
            fields["TimeCreated"] = attributes["SystemTime"] ?? ""
        case "Execution" where inSystem:
            fields["ProcessID"] = attributes["ProcessID"] ?? ""
            fields["ThreadID"] = attributes["ThreadID"] ?? ""
        case "Security" where inSystem:
            fields["Security"] = attributes["UserID"] ?? ""
        case "Data" where inEventData:
            currentDataName = attributes["Name"] ?? ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inSystem {
            switch elementName {
            case "EventID", "Version", "Level", "Task", "Opcode", "Keywords",
                 "Channel", "Computer", "EventRecordID":
                fields[elementName] = text
            case "System": inSystem = false
            default: break
            }
        } else if inEventData {
            if elementName == "Data" && !text.isEmpty {
                if currentDataName.isEmpty {
                    eventDataParts.append(text)
                } else {
                    eventDataParts.append("\(currentDataName): \(text)")
                }
            } else if elementName == "EventData" {
                fields["EventData"] = eventDataParts.joined(separator: "\n")
                inEventData = false
            }
        } else if inUserData {
            if elementName == "UserData" {
                inUserData = false
            } else if !text.isEmpty {
                if fields["UserData"] == nil { fields["UserData"] = "" }
                fields["UserData", default: ""] += "\(elementName): \(text)\n"
            }
        }
        currentText = ""
    }
}
