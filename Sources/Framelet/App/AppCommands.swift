import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Media...") {
                NotificationCenter.default.post(name: .frameletOpenMedia, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Project...") {
                NotificationCenter.default.post(name: .frameletOpenProject, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Project") {
                NotificationCenter.default.post(name: .frameletSaveProject, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Save Project As...") {
                NotificationCenter.default.post(name: .frameletSaveProjectAs, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .importExport) {
            Button("Import Segments CSV...") {
                NotificationCenter.default.post(name: .frameletImportSegmentsCSV, object: nil)
            }

            Button("Export Segments CSV...") {
                NotificationCenter.default.post(name: .frameletExportSegmentsCSV, object: nil)
            }

            Divider()

            Button("Export...") {
                NotificationCenter.default.post(name: .frameletExport, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
        }

        CommandMenu("Segment") {
            Button("Set In Point") {
                NotificationCenter.default.post(name: .frameletSetInPoint, object: nil)
            }
            .keyboardShortcut("i", modifiers: [])

            Button("Set Out Point") {
                NotificationCenter.default.post(name: .frameletSetOutPoint, object: nil)
            }
            .keyboardShortcut("o", modifiers: [])

            Button("Create Segment") {
                NotificationCenter.default.post(name: .frameletCreateSegment, object: nil)
            }
            .keyboardShortcut("b", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let frameletOpenMedia = Notification.Name("framelet.openMedia")
    static let frameletOpenProject = Notification.Name("framelet.openProject")
    static let frameletSaveProject = Notification.Name("framelet.saveProject")
    static let frameletSaveProjectAs = Notification.Name("framelet.saveProjectAs")
    static let frameletSetInPoint = Notification.Name("framelet.setInPoint")
    static let frameletSetOutPoint = Notification.Name("framelet.setOutPoint")
    static let frameletCreateSegment = Notification.Name("framelet.createSegment")
    static let frameletImportSegmentsCSV = Notification.Name("framelet.importSegmentsCSV")
    static let frameletExportSegmentsCSV = Notification.Name("framelet.exportSegmentsCSV")
    static let frameletExport = Notification.Name("framelet.export")
}
