import StagehandCore
import SwiftUI
import UniformTypeIdentifiers

/// The App Store Connect API key, kept in the Keychain. It's never written to a file.
struct AppStoreConnectSettings: View {
    @State private var coordinator = AppStoreConnectSettingsCoordinator()
    @State private var isImportingKey = false
    
    var body: some View {
        Form {
            Section {
                TextField("Issuer ID", text: $coordinator.issuerID)
                TextField("Key ID", text: $coordinator.keyID)
                
                LabeledContent("Private Key") {
                    HStack {
                        Text(coordinator.hasKey ? "Saved in the Keychain" : "None")
                            .foregroundStyle(coordinator.hasKey ? .primary : .secondary)
                        Button("Choose .p8…") { isImportingKey = true }
                    }
                }
            } footer: {
                Text("Uploads always show a plan first and wait for your confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Button("Save") { coordinator.handle(.save) }
                Button("Remove Key", role: .destructive) { coordinator.handle(.remove) }
                    .disabled(!coordinator.hasKey)
            }
            
            if let message = coordinator.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImportingKey, allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data, .data]) { result in
            if case let .success(url) = result, let file = DroppedFile.load(from: [url]).first {
                coordinator.handle(.importKey(file))
            }
        }
        .task { coordinator.handle(.load) }
    }
}

#Preview {
    AppStoreConnectSettings()
}
