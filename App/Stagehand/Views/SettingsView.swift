#if os(macOS)
import StagehandCore
import SwiftUI

/// Stagehand's settings.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("App Store Connect", systemImage: "key") {
                AppStoreConnectSettings()
            }
        }
        .frame(width: 520, height: 360)
    }
}

#Preview {
    SettingsView()
}
#endif
