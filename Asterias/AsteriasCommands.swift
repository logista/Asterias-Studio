import AppKit
import SwiftUI

struct AsteriasCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Asterias Studio") {
                AsteriasHelp.openAboutPanel()
            }
        }

        CommandGroup(replacing: .help) {
            Button("Asterias Studio Help") {
                AsteriasHelp.openHelpPage(named: "AsteriasStudioHelp")
            }
            .keyboardShortcut("?", modifiers: [.command])

            Button("Import and Export Help") {
                AsteriasHelp.openHelpPage(named: "AsteriasImportExportHelp")
            }
        }
    }
}

enum AsteriasHelp {
    @MainActor
    static func openAboutPanel() {
        let credits = NSAttributedString(
            string: "©2026 Barbara Tozier assisted by Codex.\nBased on work ©1999 Mars Saxman\nLicenced under GPL2.0",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Asterias Studio",
            .applicationVersion: Bundle.main.appBuildDescription,
            .credits: credits
        ])
    }

    static func openHelpPage(named resourceName: String) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "html") else {
            NSSound.beep()
            return
        }

        NSWorkspace.shared.open(url)
    }
}
