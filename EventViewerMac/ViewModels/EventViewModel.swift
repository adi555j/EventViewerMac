import SwiftUI
import UniformTypeIdentifiers

@MainActor
class EventViewModel: ObservableObject {
    @Published var events: [EvtxEvent] = []
    @Published var filteredEvents: [EvtxEvent] = []
    @Published var selectedEvent: EvtxEvent?
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var errorMessage: String?
    @Published var fileName: String?
    @Published var searchText = "" { didSet { applyFilters() } }
    @Published var selectedLevels: Set<Int> = [] { didSet { applyFilters() } }
    @Published var sortOrder: SortOrder = .newestFirst { didSet { applyFilters() } }

    enum SortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
    }

    var eventCount: Int { filteredEvents.count }
    var totalCount: Int { events.count }

    func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Event Log File"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "evtx") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(url: url)
        }
    }

    func loadFile(url: URL) {
        fileName = url.lastPathComponent
        isLoading = true
        loadingProgress = 0
        errorMessage = nil
        events = []
        filteredEvents = []
        selectedEvent = nil

        Task.detached {
            do {
                let parser = try EvtxParser(url: url)
                let parsed = try parser.parse { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.loadingProgress = progress
                    }
                }
                await MainActor.run { [weak self] in
                    self?.events = parsed
                    self?.applyFilters()
                    self?.isLoading = false
                    if parsed.isEmpty {
                        self?.errorMessage = "No events found in file."
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }

    func applyFilters() {
        var result = events

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { event in
                event.providerName.lowercased().contains(query) ||
                event.message.lowercased().contains(query) ||
                event.channel.lowercased().contains(query) ||
                event.computer.lowercased().contains(query) ||
                String(event.eventId).contains(query) ||
                event.levelName.lowercased().contains(query)
            }
        }

        if !selectedLevels.isEmpty {
            result = result.filter { selectedLevels.contains($0.level) }
        }

        switch sortOrder {
        case .newestFirst: result.sort { $0.timestamp > $1.timestamp }
        case .oldestFirst: result.sort { $0.timestamp < $1.timestamp }
        }

        filteredEvents = result
    }

    func toggleLevel(_ level: Int) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
    }

    func clearFilters() {
        searchText = ""
        selectedLevels = []
    }

    var availableLevels: [(Int, String, Int)] {
        var counts: [Int: Int] = [:]
        for event in events {
            counts[event.level, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { level, count in
            let name: String
            switch level {
            case 1: name = "Critical"
            case 2: name = "Error"
            case 3: name = "Warning"
            case 4: name = "Information"
            case 5: name = "Verbose"
            default: name = "Level \(level)"
            }
            return (level, name, count)
        }
    }
}
