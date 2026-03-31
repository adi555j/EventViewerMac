import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: EventViewModel
    @State private var tableSelection: EvtxEvent.ID?

    var body: some View {
        VSplitView {
            eventTable
                .frame(minHeight: 200)
            detailPane
                .frame(minHeight: 150, idealHeight: 250)
        }
        .toolbar { toolbarContent }
        .searchable(text: $viewModel.searchText, prompt: "Search events...")
        .navigationTitle(viewModel.fileName ?? "Event Viewer")
        .navigationSubtitle(statusText)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .overlay {
            if viewModel.isLoading {
                loadingOverlay
            } else if viewModel.events.isEmpty && viewModel.errorMessage == nil {
                emptyState
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Event Table

    private var eventTable: some View {
        Table(viewModel.filteredEvents, selection: $tableSelection) {
            TableColumn("") { event in
                Image(systemName: event.levelSymbol)
                    .foregroundColor(levelColor(event.level))
                    .help(event.levelName)
            }
            .width(24)

            TableColumn("Date/Time") { event in
                Text(shortDate(event.timestamp))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 170)

            TableColumn("Level") { event in
                Text(event.levelName)
                    .foregroundColor(levelColor(event.level))
            }
            .width(min: 60, ideal: 80)

            TableColumn("Event ID") { event in
                Text("\(event.eventId)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 50, ideal: 65)

            TableColumn("Source") { event in
                Text(event.providerName)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 180)

            TableColumn("Message") { event in
                Text(event.message.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(2)
                    .foregroundColor(.secondary)
            }
            .width(min: 150, ideal: 400)
        }
        .onChange(of: tableSelection) { _, newValue in
            viewModel.selectedEvent = viewModel.filteredEvents.first { $0.id == newValue }
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let event = viewModel.selectedEvent {
            EventDetailView(event: event)
        } else {
            VStack {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("Select an event to view details")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.openFile()
            } label: {
                Label("Open", systemImage: "folder")
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(viewModel.availableLevels, id: \.0) { level, name, count in
                    Button {
                        viewModel.toggleLevel(level)
                    } label: {
                        HStack {
                            if viewModel.selectedLevels.contains(level) {
                                Image(systemName: "checkmark")
                            }
                            Text("\(name) (\(count))")
                        }
                    }
                }
                if !viewModel.selectedLevels.isEmpty {
                    Divider()
                    Button("Clear Filters") {
                        viewModel.clearFilters()
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .disabled(viewModel.events.isEmpty)
        }

        ToolbarItem(placement: .automatic) {
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(EventViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .disabled(viewModel.events.isEmpty)
        }
    }

    // MARK: - Overlays

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView(value: viewModel.loadingProgress) {
                Text("Loading events...")
            }
            .frame(width: 200)
            Text("\(Int(viewModel.loadingProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(30)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Event Log Loaded")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Open a .evtx file or drag and drop one here")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Open File...") {
                viewModel.openFile()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        guard !viewModel.events.isEmpty else { return "" }
        if viewModel.filteredEvents.count == viewModel.totalCount {
            return "\(viewModel.totalCount) events"
        }
        return "\(viewModel.eventCount) of \(viewModel.totalCount) events"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            if url.pathExtension.lowercased() == "evtx" {
                Task { @MainActor in
                    viewModel.loadFile(url: url)
                }
            }
        }
        return true
    }
}
