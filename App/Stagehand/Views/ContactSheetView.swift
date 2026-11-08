import StagehandCore
import StagehandModel
import SwiftUI

/// Slides as rows and the lineup's targets as columns, grouped by device class, with a thumbnail in every cell. A
/// slide that's off for a device has a "+" there instead. Templates dropped from the sidebar become slides.
struct ContactSheetView: View {
    private static let cellWidth: Double = 150
    
    @Bindable private var coordinator: ProjectCoordinator
    private let runs: RunStatusSource?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    
    init(coordinator: ProjectCoordinator, runs: RunStatusSource?) {
        self.coordinator = coordinator
        self.runs = runs
    }
    
    var body: some View {
        let sheet = coordinator.contactSheet
        
        ScrollView([.horizontal, .vertical]) {
            if let setID = sheet.setID, !sheet.rows.isEmpty {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        
                        ForEach(sheet.columns) { column in
                            ColumnHeader(target: column.target)
                                .frame(width: Self.cellWidth, alignment: .leading)
                        }
                    }
                    
                    ForEach(sheet.rows) { row in
                        GridRow {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(row.number)")
                                    .font(.title2.bold())
                                    .monospacedDigit()
                                
                                Text(row.title)
                                    .font(.callout)
                                    .lineLimit(3)
                                
                                if !row.alsoIn.isEmpty {
                                    Text("Also in \(row.alsoIn.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 110, alignment: .leading)
                            
                            ForEach(sheet.columns) { column in
                                let cell = CellID(setID: setID, slideID: row.slideID, targetID: column.target.id)
                                let device = column.target.deviceClass
                                
                                if row.excludedDevices.contains(device) {
                                    OffCell(device: device, width: Self.cellWidth, aspectRatio: column.target.aspectRatio) {
                                        coordinator.handle(.setSlideOn(row.slideID, device, true))
                                    }
                                } else {
                                    ContactSheetCell(
                                        thumbnail: coordinator.thumbnail(for: cell, width: Self.cellWidth * displayScale),
                                        status: coordinator.status(for: cell),
                                        run: runs?.status(for: cell),
                                        isSelected: coordinator.selection.cell == cell,
                                        width: Self.cellWidth,
                                        aspectRatio: column.target.aspectRatio,
                                        deviceName: device.displayName,
                                        onIntent: { handle($0, cell: cell, target: column.target, slideID: row.slideID) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .dropDestination(for: SheetDrop.self) { items, _ in
                    handleDrop(items)
                }
            } else {
                ContentUnavailableView {
                    Label("No Slides Yet", systemImage: "rectangle.stack")
                } description: {
                    Text("Drag a template here from the sidebar, or start one from a template.")
                } actions: {
                    ForEach(coordinator.project.style.templates) { template in
                        Button("New Slide from \(template.name)") { coordinator.handle(.addSlide(template: template.id)) }
                    }
                }
                .padding(60)
                .dropDestination(for: SheetDrop.self) { items, _ in
                    handleDrop(items)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            let missing = coordinator.devicesMissingBezels
            
            if !missing.isEmpty {
                HStack {
                    Image(systemName: "iphone.gen3.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    
                    Text("No bezels for \(missing.map(\.displayName).joined(separator: ", ")) yet, so devices draw in a plain frame.")
                    
                    Spacer()
                    
                    Button("Download Bezels…") { openWindow(id: LibraryWindow.id) }
                }
                .padding(10)
                .background(.regularMaterial)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            coordinator.handle(.importCaptures(DroppedFile.load(from: urls), .sheet))
            return true
        }
        .overlay(alignment: .bottom) {
            if !coordinator.importIssues.isEmpty {
                ImportIssuesBanner(issues: coordinator.importIssues, onDismiss: { coordinator.handle(.dismissImportIssues) })
                    .padding()
            }
        }
    }
    
    /// Screenshots import (matched to slides by their names), and templates from the sidebar make slides.
    private func handleDrop(_ items: [SheetDrop]) {
        let files = items.compactMap { if case let .file(url) = $0 { url } else { nil } }
        let templates = items.compactMap { if case let .text(text) = $0 { TemplateDrag.templateID(text) } else { nil } }
        
        if !files.isEmpty {
            coordinator.handle(.importCaptures(DroppedFile.load(from: files), .sheet))
        }
        
        for template in templates {
            coordinator.handle(.addSlide(template: template))
        }
    }
    
    private func handle(_ intent: ContactSheetCell.Intent, cell: CellID, target: DeviceTarget, slideID: Slide.ID) {
        switch intent {
        case .hideOnDevice:
            coordinator.handle(.setSlideOn(slideID, target.deviceClass, false))
        case .open:
            coordinator.handle(.selectCell(cell))
        case let .drop(urls):
            let key = coordinator.project.slides[slideID]?.captureKey[target.deviceClass] ?? ""
            coordinator.handle(.importCaptures(DroppedFile.load(from: urls), .cell(key: key, deviceClass: target.deviceClass)))
        case .recapture:
            runs?.recapture(cell)
        case .removeCapture:
            if let key = coordinator.project.slides[slideID]?.captureKey[target.deviceClass] {
                coordinator.handle(.removeCapture(CaptureAddress(key: key, deviceClass: target.deviceClass, locale: coordinator.selection.locale)))
            }
        case .openResultBundle:
            if let url = runs?.resultBundle(for: cell) {
                openURL(url)
            }
        }
    }
}

private struct ColumnHeader: View {
    private let target: DeviceTarget
    
    init(target: DeviceTarget) {
        self.target = target
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(target.name)
                    .font(.headline)
                    .lineLimit(2)
                
                if target.isRequired {
                    Image(systemName: "asterisk")
                        .font(.caption2.bold())
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Required")
                        .help("App Store Connect requires this size")
                }
            }
            
            Text("\(target.exportSize.width) × \(target.exportSize.height)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct ContactSheetCell: View {
    enum Intent {
        case open
        case drop([URL])
        case recapture
        case removeCapture
        case openResultBundle
        case hideOnDevice
    }
    
    private let thumbnail: CGImage?
    private let status: CellStatus
    private let run: RunCellStatus?
    private let isSelected: Bool
    private let width: Double
    private let aspectRatio: Double
    private let deviceName: String
    private let onIntent: (Intent) -> Void
    @State private var isTargeted: Bool
    
    init(thumbnail: CGImage?, status: CellStatus, run: RunCellStatus?, isSelected: Bool, width: Double, aspectRatio: Double, deviceName: String, onIntent: @escaping (Intent) -> Void) {
        self.thumbnail = thumbnail
        self.status = status
        self.run = run
        self.isSelected = isSelected
        self.width = width
        self.aspectRatio = aspectRatio
        self.deviceName = deviceName
        self.onIntent = onIntent
        self.isTargeted = false
    }
    
    var body: some View {
        Button {
            onIntent(.open)
        } label: {
            ZStack {
                if let thumbnail {
                    Image(pixels: thumbnail)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: width, height: width / aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isTargeted ? Color.accentColor : isSelected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.3), lineWidth: isTargeted || isSelected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                StatusBadge(status: status, run: run)
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .pointerHoverEffect()
        .accessibilityLabel("Open on the canvas")
        .help(status.flags.map(\.message).joined(separator: "\n"))
        .dropDestination(for: URL.self) { urls, _ in
            onIntent(.drop(urls))
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .contextMenu {
            Button("Open on Canvas") { onIntent(.open) }
            #if os(macOS)
            Button("Recapture") { onIntent(.recapture) }
            
            if case .failed = run {
                Button("Open Result in Xcode") { onIntent(.openResultBundle) }
            }
            #endif
            Button("Remove Capture", role: .destructive) { onIntent(.removeCapture) }
            Divider()
            Button("Hide Slide on \(deviceName)") { onIntent(.hideOnDevice) }
        }
    }
}

/// A slide that's off for a device: no screenshot there, and a button to turn it on.
private struct OffCell: View {
    private let device: DeviceClass
    private let width: Double
    private let aspectRatio: Double
    private let onShow: () -> Void
    
    init(device: DeviceClass, width: Double, aspectRatio: Double, onShow: @escaping () -> Void) {
        self.device = device
        self.width = width
        self.aspectRatio = aspectRatio
        self.onShow = onShow
    }
    
    var body: some View {
        Button(action: onShow) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.title2)
                
                Text("Show on \(device.displayName)")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(width: width, height: width / aspectRatio)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
        .pointerHoverEffect()
        .help("This slide is off for \(device.displayName), so it isn't exported or uploaded there")
    }
}

private struct StatusBadge: View {
    private let status: CellStatus
    private let run: RunCellStatus?
    
    init(status: CellStatus, run: RunCellStatus?) {
        self.status = status
        self.run = run
    }
    
    var body: some View {
        Group {
            switch run {
            case .queued:
                Image(systemName: "clock").foregroundStyle(.secondary)
            case .capturing:
                ProgressView().controlSize(.small)
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            case .captured, nil:
                switch status.severity {
                case .error: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                case .warning: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                case .info, nil: EmptyView()
                }
            }
        }
        .padding(3)
        .background(.regularMaterial, in: Circle())
        .accessibilityLabel(status.flags.map(\.message).joined(separator: ", "))
    }
}

/// What can be dropped between the contact sheet's cells: screenshot files, or templates from the sidebar.
///
/// One drop destination takes both, files first. A text-only destination nested inside the sheet's file destination
/// could take a dragged file as its text and drop it on the floor.
enum SheetDrop: Transferable {
    case file(URL)
    case text(String)
    
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in SheetDrop.file(url) })
        ProxyRepresentation(importing: { (text: String) in SheetDrop.text(text) })
    }
}

/// The screenshots a drop refused, and why, over the contact sheet or the canvas.
struct ImportIssuesBanner: View {
    private let issues: [CaptureImportError]
    private let onDismiss: () -> Void
    
    init(issues: [CaptureImportError], onDismiss: @escaping () -> Void) {
        self.issues = issues
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading) {
                ForEach(issues, id: \.self) { issue in
                    Text(issue.errorDescription ?? "")
                }
            }
            
            Spacer()
            
            Button("Dismiss", action: onDismiss)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    ContactSheetView(coordinator: coordinator, runs: nil)
        .task { await coordinator.start() }
        .frame(width: 700, height: 600)
}
