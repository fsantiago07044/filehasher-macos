import SwiftUI
#if CHANNEL_STANDALONE
import Sparkle
#endif

@main
struct FileHasherApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

#if CHANNEL_STANDALONE
    // Sparkle drives updates in the standalone edition only. The App Store
    // edition contains no Sparkle code (self-updating is prohibited there).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
#endif

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
#if CHANNEL_STANDALONE
                Divider()
                Button("Check for Updates…") {
                    updaterController.updater.checkForUpdates()
                }
#endif
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
