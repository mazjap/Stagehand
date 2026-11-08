import StagehandCore
import StagehandModel
import SwiftUI

/// Each set's first three slides as App Store search results show them: three portrait screenshots side by side,
/// or one landscape one.
struct SearchPreviewSheet: View {
    @Bindable private var coordinator: ProjectCoordinator
    private let onDismiss: () -> Void
    @Environment(\.displayScale) private var displayScale
    
    init(coordinator: ProjectCoordinator, onDismiss: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(coordinator.project.sets) { set in
                        ForEach(set.resolvedTargets()) { target in
                            SearchResult(coordinator: coordinator, set: set, target: target, displayScale: displayScale)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Search Preview")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 600)
    }
}

private struct SearchResult: View {
    private static let width: Double = 390
    
    @Bindable private var coordinator: ProjectCoordinator
    private let set: ShotSet
    private let target: DeviceTarget
    private let displayScale: Double
    
    init(coordinator: ProjectCoordinator, set: ShotSet, target: DeviceTarget, displayScale: Double) {
        self.coordinator = coordinator
        self.set = set
        self.target = target
        self.displayScale = displayScale
    }
    
    var body: some View {
        let portrait = target.aspectRatio < 1
        let count = portrait ? 3 : 1
        let spacing = 6.0
        let thumbnailWidth = (Self.width - spacing * Double(count - 1)) / Double(count)
        let slides = Array(set.slideIDs.prefix(count))
        let accent = coordinator.project.style.color("accent").color
        
        VStack(alignment: .leading, spacing: 10) {
            Text("\(set.name) · \(target.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.gradient)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.project.name)
                        .font(.headline)
                    Text(coordinator.project.bundleID ?? "Your app's subtitle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("Get")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            
            HStack(spacing: spacing) {
                ForEach(slides, id: \.self) { slideID in
                    let cell = CellID(setID: set.id, slideID: slideID, targetID: target.id)
                    
                    Group {
                        if let thumbnail = coordinator.thumbnail(for: cell, width: thumbnailWidth * displayScale) {
                            Image(pixels: thumbnail)
                                .resizable()
                                .interpolation(.high)
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: thumbnailWidth, height: thumbnailWidth / target.aspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .frame(width: Self.width)
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    SearchPreviewSheet(coordinator: coordinator, onDismiss: {})
        .task { await coordinator.start() }
}
