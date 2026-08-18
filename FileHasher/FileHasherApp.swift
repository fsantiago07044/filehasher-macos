import SwiftUI

@main
struct FileHasherApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

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
            // Single-window utility; "New Window" makes no sense here.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("FileHasher Help") { openWindow(id: "help") }
                    .keyboardShortcut("?", modifiers: .command)
                Divider()
                Button("Support Website") {
                    NSWorkspace.shared.open(
                        URL(string: "https://fabianasantiago.com/filehasher/support/")!)
                }
                Button("Privacy Policy") {
                    NSWorkspace.shared.open(
                        URL(string: "https://fabianasantiago.com/privacy-policy/")!)
                }
            }
        }

        Window("FileHasher Help", id: "help") {
            HelpView()
                .frame(minWidth: 640, minHeight: 440)
        }
        .defaultSize(width: 820, height: 560)
    }
}
