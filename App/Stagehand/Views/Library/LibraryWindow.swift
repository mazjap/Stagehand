import StagehandCore
import StagehandModel
import SwiftUI
import UniformTypeIdentifiers

/// The library's template sets, and its bezels: Apple Design Resources' products to download (Mac only, since
/// installing mounts a disk image), the bezels already in the library, and the default for each device class.
struct LibraryWindow: View {
    static let id = "library"
    
    @State private var coordinator = LibraryCoordinator()
    @State private var isImporting = false
    @State private var importClass: DeviceClass = .phone
    @State private var importModel = ""
    @State private var importColor = ""
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    LabeledContent("Folder", value: coordinator.libraryURL?.path(percentEncoded: false) ?? "Loading…")
                    LabeledContent("iCloud Drive", value: coordinator.isUsingICloud ? "Yes" : "No, a local folder")
                }
                
                Section("Template Sets") {
                    if coordinator.styles.isEmpty {
                        Text("Save a project's template set to the library (File › Save Template Set to Library), or make one with New Template Set.")
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(coordinator.styles) { style in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(style.name)
                                Text("Version \(style.version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Open") { openURL(style.url) }
                            
                            #if os(macOS)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([style.url])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Show \(style.name) in Finder")
                            .help("Show in Finder")
                            #endif
                        }
                    }
                    
                    Button("Refresh") { coordinator.handle(.load) }
                }
                
                #if os(macOS)
                AppleBezelsSection(coordinator: coordinator)
                #endif
                
                Section("Bezels in the Library") {
                    let bezels = coordinator.bezels.bezels.values.sorted { ($0.deviceClass.rawValue, $0.name) < ($1.deviceClass.rawValue, $1.name) }
                    
                    if bezels.isEmpty {
                        Text("Download Apple's product bezels above. They stay in the library, never in a repository, and templates keep the bezel they pinned until you update it.")
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(bezels) { bezel in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bezel.name)
                                Text("\(bezel.deviceClass.displayName) · \(bezel.model) · \(bezel.color) · screen \(bezel.screenRect.width) × \(bezel.screenRect.height)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if coordinator.bezels.defaults[bezel.deviceClass] == bezel.id {
                                Text("Default")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            } else {
                                Button("Make Default") { coordinator.handle(.setDefault(bezel.id, bezel.deviceClass)) }
                            }
                            
                            Button {
                                coordinator.handle(.remove(bezel.id))
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(bezel.name)")
                        }
                    }
                }
                
                Section("Import a Bezel by Hand") {
                    Picker("Device Class", selection: $importClass) {
                        ForEach(DeviceClass.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    
                    TextField("Model", text: $importModel, prompt: Text("iPhone 17 Pro Max"))
                    TextField("Color", text: $importColor, prompt: Text("Deep Blue"))
                    
                    Button("Choose PNG…") { isImporting = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Library")
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.png]) { result in
                if case let .success(url) = result, let file = DroppedFile.load(from: [url]).first {
                    coordinator.handle(.importBezel(file, deviceClass: importClass, model: importModel, color: importColor))
                }
            }
            .alert(coordinator.alert?.title ?? "", item: $coordinator.alert) { _ in
                Button("OK") {}
            } message: { alert in
                Text(alert.message)
            }
        }
        .frame(minWidth: 560, minHeight: 600)
        .task { coordinator.handle(.load) }
        #if os(macOS)
        .sheet(isPresented: Binding(get: { coordinator.pendingLicense != nil }, set: { if !$0 { coordinator.handle(.declineLicense) } })) {
            if let pending = coordinator.pendingLicense {
                LicenseSheet(downloaded: pending) {
                    coordinator.handle(.agreeToLicense)
                } onDecline: {
                    coordinator.handle(.declineLicense)
                }
            }
        }
        #endif
    }
}

#if os(macOS)
/// Apple Design Resources' bezels, by product: download, update, or see what's installed.
private struct AppleBezelsSection: View {
    @Bindable private var coordinator: LibraryCoordinator
    
    init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }
    
    var body: some View {
        Section {
            if coordinator.appleProducts.isEmpty {
                HStack {
                    if coordinator.isLoadingAppleBezels {
                        ProgressView()
                            .controlSize(.small)
                    }
                    
                    Text(coordinator.isLoadingAppleBezels ? "Loading Apple's list…" : "Apple's list hasn't loaded.")
                        .foregroundStyle(.secondary)
                }
            }
            
            ForEach(coordinator.appleProducts.filter { !$0.deviceClasses.isEmpty }) { product in
                ProductRow(coordinator: coordinator, product: product)
            }
        } header: {
            HStack {
                Text("Apple Design Resources")
                
                Spacer()
                
                Button("Check for Updates") { coordinator.handle(.loadAppleBezels) }
                    .disabled(coordinator.isLoadingAppleBezels || coordinator.libraryURL == nil)
            }
        } footer: {
            Text("Each download is a disk image of PNGs (up to about 450 MB) with Apple's license agreement, which you'll be asked to agree to before it's opened.")
        }
        .task(id: coordinator.libraryURL) {
            if coordinator.libraryURL != nil, coordinator.appleProducts.isEmpty {
                coordinator.handle(.loadAppleBezels)
            }
        }
    }
}

private struct ProductRow: View {
    @Bindable private var coordinator: LibraryCoordinator
    private let product: AppleBezelProduct
    
    init(coordinator: LibraryCoordinator, product: AppleBezelProduct) {
        self.coordinator = coordinator
        self.product = product
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(product.name)
                
                Text(product.deviceClasses.map(\.displayName).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if coordinator.installing.contains(product.url) {
                ProgressView()
                    .controlSize(.small)
                
                Text("Installing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let progress = coordinator.progress[product.url] {
                ProgressView(value: progress)
                    .frame(width: 100)
            } else if coordinator.hasUpdate(product) {
                Button("Update") { coordinator.handle(.download(product)) }
                    .help("Apple updated this file. It's added next to the old bezels; templates keep theirs until you update them.")
            } else if coordinator.isInstalled(product) {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.green)
                
                // NOTE: - For a color or model that was removed to keep one bezel per device. Bezels already in the
                // library come back as they were; an imported bezel is never overwritten.
                Button("Download Again") { coordinator.handle(.download(product)) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Download it again, to get back a color or model you removed")
            } else {
                Button("Download") { coordinator.handle(.download(product)) }
            }
        }
    }
}

/// Apple's license agreement for a downloaded disk image, which has to be agreed to before it's opened.
private struct LicenseSheet: View {
    private let downloaded: DownloadedBezels
    private let onAgree: () -> Void
    private let onDecline: () -> Void
    
    init(downloaded: DownloadedBezels, onAgree: @escaping () -> Void, onDecline: @escaping () -> Void) {
        self.downloaded = downloaded
        self.onAgree = onAgree
        self.onDecline = onDecline
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("License Agreement for \(downloaded.product.name)")
                .font(.title3.bold())
            
            Text("Apple's bezels come with this agreement. Stagehand opens the disk image only if you agree.")
                .foregroundStyle(.secondary)
            
            ScrollView {
                Text(downloaded.license ?? "")
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            
            HStack {
                Spacer()
                
                Button("Disagree", role: .cancel, action: onDecline)
                    .keyboardShortcut(.cancelAction)
                
                Button("Agree", action: onAgree)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }
}
#endif

#Preview {
    LibraryWindow()
}
