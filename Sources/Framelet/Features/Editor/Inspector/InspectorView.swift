import SwiftUI

struct InspectorView: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $store.selectedInspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            ScrollView {
                switch store.selectedInspectorTab {
                case .segments:
                    SegmentInspector(store: store)
                case .media:
                    MediaInspector(store: store)
                case .export:
                    ExportInspector(store: store)
                case .diagnostics:
                    DiagnosticsInspector(store: store)
                }
            }
        }
        .background(.regularMaterial)
    }
}
