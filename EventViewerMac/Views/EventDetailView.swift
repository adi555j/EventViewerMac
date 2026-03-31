import SwiftUI

struct EventDetailView: View {
    let event: EvtxEvent
    @State private var showingXml = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            if showingXml {
                xmlView
            } else {
                propertiesView
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var headerBar: some View {
        HStack {
            Label(event.levelName, systemImage: event.levelSymbol)
                .font(.headline)
                .foregroundColor(levelColor(event.level))

            Text("Event \(event.eventId)")
                .font(.headline)

            Spacer()

            Picker("View", selection: $showingXml) {
                Text("Properties").tag(false)
                Text("XML").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(event.xmlContent, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy XML to clipboard")
        }
        .padding(10)
    }

    private var propertiesView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.fixed(130), alignment: .trailing),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 6) {
                propertyRow("Log Name:", event.channel)
                propertyRow("Source:", event.providerName)
                propertyRow("Event ID:", "\(event.eventId)")
                propertyRow("Level:", event.levelName)
                propertyRow("Date/Time:", formattedDate(event.timestamp))
                propertyRow("Computer:", event.computer)
                propertyRow("Record ID:", "\(event.recordId)")
                if !event.userSID.isEmpty {
                    propertyRow("User:", event.userSID)
                }
                propertyRow("Process ID:", "\(event.processId)")
                propertyRow("Thread ID:", "\(event.threadId)")
                if !event.keywords.isEmpty && event.keywords != "0" {
                    propertyRow("Keywords:", event.keywords)
                }
            }
            .padding()

            if !event.message.isEmpty {
                Divider().padding(.horizontal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event Data")
                        .font(.headline)
                    Text(event.message)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                }
                .padding()
            }
        }
    }

    private var xmlView: some View {
        ScrollView {
            Text(prettyXml(event.xmlContent))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    @ViewBuilder
    private func propertyRow(_ label: String, _ value: String) -> some View {
        Text(label)
            .font(.subheadline)
            .foregroundColor(.secondary)
        Text(value)
            .font(.subheadline)
            .textSelection(.enabled)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .long
        return formatter.string(from: date)
    }

    private func prettyXml(_ xml: String) -> String {
        guard let data = xml.data(using: .utf8),
              let doc = try? XMLDocument(data: data, options: .nodePrettyPrint) else {
            return xml
        }
        return doc.xmlString(options: .nodePrettyPrint)
    }

    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return .red
        case 2: return .red
        case 3: return .orange
        case 4: return .blue
        case 5: return .gray
        default: return .primary
        }
    }
}
