import SwiftUI

@main
struct EventViewerMacApp: App {
    @StateObject private var viewModel = EventViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    viewModel.openFile()
                }
                .keyboardShortcut("o")
            }
        }
    }
}
