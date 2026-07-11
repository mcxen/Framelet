import SwiftUI

struct SettingsView: View {
    @AppStorage("preferKeyframeSnap") private var preferKeyframeSnap = true
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("automaticallyCheckForUpdates") private var automaticallyCheckForUpdates = true
    @State private var updater = UpdateService.shared

    var body: some View {
        Form {
            Picker("Appearance", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.titleKey).tag(theme.rawValue)
                }
            }

            Picker("Language", selection: $appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.titleKey).tag(language.rawValue)
                }
            }

            Toggle("Snap quick cuts to the previous keyframe when available", isOn: $preferKeyframeSnap)
            Text("Framelet uses FFmpeg stream copy for lossless exports. Frame-exact smart cutting is planned for a later version.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Section("About") {
                LabeledContent("Version", value: updater.currentVersion)
                Toggle("Automatically check for updates", isOn: $automaticallyCheckForUpdates)
                HStack {
                    updateStatus
                    Spacer()
                    if case .available = updater.state {
                        Button("Download and Install") { Task { await updater.install() } }
                    } else {
                        Button("Check for Updates") { Task { await updater.check() } }
                            .disabled(updater.state == .checking)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .task {
            if automaticallyCheckForUpdates, updater.state == .idle { await updater.check() }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.state {
        case .idle:
            Text("Updates are delivered from GitHub Releases.")
        case .checking:
            ProgressView().controlSize(.small)
            Text("Checking for updates…")
        case .upToDate:
            Text("Framelet is up to date.")
        case let .available(version):
            Text("Version \(version) is available.")
        case let .downloading(progress):
            ProgressView(value: progress).frame(width: 90)
            Text("Installing update…")
        case let .failed(message):
            Text(LocalizedStringKey(message)).foregroundStyle(.red)
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            "Follow System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            "Follow System"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: rawValue)
        case .simplifiedChinese:
            Locale(identifier: rawValue)
        }
    }
}
