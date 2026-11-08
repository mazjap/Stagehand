import StagehandCore
import SwiftUI

/// Uploads to App Store Connect: first a dry run that shows what would change, then an explicit confirmation.
struct UploadSheet: View {
    @State private var coordinator: UploadCoordinator
    @State private var isConfirming = false
    private let onDismiss: () -> Void
    
    init(project: ProjectCoordinator, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.coordinator = UploadCoordinator(project: project)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.phase {
                case .idle:
                    ContentUnavailableView {
                        Label("Upload to App Store Connect", systemImage: "icloud.and.arrow.up")
                    } description: {
                        Text("Check what an upload would change first. Nothing is sent until you confirm.")
                    } actions: {
                        Button("Check What Would Change") { coordinator.handle(.plan) }
                            .buttonStyle(.borderedProminent)
                    }
                case .planning:
                    ProgressView("Comparing with App Store Connect…")
                case let .planned(plans):
                    List(plans) { plan in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(plan.customProductPageID.map { "Custom page \($0) · " } ?? "")\(plan.locale) · \(plan.target.name)")
                                .font(.headline)
                            Text(plan.localization == nil ? "The version has no \(plan.locale) localization, so this is skipped." : plan.summary)
                                .foregroundStyle(plan.hasChanges ? .primary : .secondary)
                        }
                    }
                case let .uploading(done, total):
                    ProgressView("Uploading…", value: Double(done), total: Double(max(total, 1)))
                        .padding(40)
                case let .finished(message):
                    ContentUnavailableView(message, systemImage: "checkmark.circle")
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Couldn't Upload", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { coordinator.handle(.plan) }
                    }
                }
            }
            .navigationTitle("App Store Connect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
                
                ToolbarItem(placement: .automatic) {
                    Toggle("Keep App Store Connect's Order", isOn: Binding(get: { coordinator.keepsOrder }, set: { coordinator.handle(.setKeepsOrder($0)) }))
                        .help("Adds and replaces screenshots without reordering them, for an order changed in App Store Connect by hand. New screenshots go at the end.")
                }
                
                if case .planned = coordinator.phase {
                    let changes = coordinator.totalChanges
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Upload…") { isConfirming = true }
                            .disabled(!coordinator.plans.contains(where: \.hasChanges))
                            .confirmationDialog("Upload to App Store Connect?", isPresented: $isConfirming) {
                                Button("Upload \(changes.uploads) and Delete \(changes.deletions)", role: .destructive) {
                                    coordinator.handle(.confirmUpload)
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(coordinator.keepsOrder
                                    ? "This uploads \(changes.uploads) screenshots and deletes \(changes.deletions), as listed, keeping App Store Connect's order."
                                    : "This uploads \(changes.uploads) screenshots, deletes \(changes.deletions), and reorders the screenshots in App Store Connect, as listed.")
                            }
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 440)
    }
}

#Preview {
    UploadSheet(project: ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture()))), onDismiss: {})
}
