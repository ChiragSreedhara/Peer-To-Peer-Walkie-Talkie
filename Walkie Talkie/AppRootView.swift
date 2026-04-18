import SwiftUI

enum WalkieMode: String, CaseIterable {
    case sync = "Live Voice"
    case async = "Voice Notes"
}

struct AppRootView: View {
    @State private var selectedMode: WalkieMode = .sync

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedMode) {
                ForEach(WalkieMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedMode {
            case .sync:
                SyncContentView()
            case .async:
                AsyncContentView()
            }
        }
    }
}
