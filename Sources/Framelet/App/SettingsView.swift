import SwiftUI

struct SettingsView: View {
    @AppStorage("preferKeyframeSnap") private var preferKeyframeSnap = true

    var body: some View {
        Form {
            Toggle("Snap quick cuts to the previous keyframe when available", isOn: $preferKeyframeSnap)
            Text("Framelet uses FFmpeg stream copy for lossless exports. Frame-exact smart cutting is planned for a later version.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460)
    }
}
