import SwiftUI

@main
struct FileHasherApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("FileHasher", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 640)
        }
        .defaultSize(width: 900, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FileHasher") { model.showAbout() }
            }
            // Single-window utility — "New Window" makes no sense here.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
