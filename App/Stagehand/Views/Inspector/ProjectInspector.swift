import StagehandCore
import StagehandModel
import SwiftUI
import UniformTypeIdentifiers

/// The project's devices and export sizes, the selected custom product page, the project's locales and fonts, and
/// the app link.
struct ProjectInspector: View {
    @Bindable private var coordinator: ProjectCoordinator
    @State private var isImportingFonts = false
    @State private var isImportingStrings = false
    @State private var isExportingStrings = false
    @State private var addingDevice: DeviceClass?
    @State private var removingDevice: DeviceClass?
    
    init(coordinator: ProjectCoordinator) {
        self.coordinator = coordinator
        self.addingDevice = nil
        self.removingDevice = nil
    }
    
    var body: some View {
        let project = coordinator.project
        let missing = DeviceClass.allCases.filter { !project.devices.contains($0) }
        
        InspectorSection("Devices") {
            ForEach(project.devices, id: \.self) { device in
                HStack {
                    Label(device.displayName, systemImage: Self.symbol(for: device))
                    
                    Spacer()
                    
                    Text("\(project.slides(in: project.mainLineup, on: device).count) slides")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        removingDevice = device
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(project.devices.count == 1)
                    .accessibilityLabel("Remove \(device.displayName)")
                }
            }
            
            if !missing.isEmpty {
                Menu {
                    ForEach(missing, id: \.self) { device in
                        Button(device.displayName) {
                            if project.slides.isEmpty {
                                coordinator.handle(.addDevice(device, includeExistingSlides: true))
                            } else {
                                addingDevice = device
                            }
                        }
                    }
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .confirmationDialog(
            "Show the existing slides on \(addingDevice?.displayName ?? "")?",
            isPresented: Binding(get: { addingDevice != nil }, set: { if !$0 { addingDevice = nil } }),
            presenting: addingDevice
        ) { device in
            Button("Show Existing Slides") { coordinator.handle(.addDevice(device, includeExistingSlides: true)) }
            Button("Only New Slides") { coordinator.handle(.addDevice(device, includeExistingSlides: false)) }
        } message: { device in
            Text("Either way, each slide can be turned on or off for \(device.displayName) in the Slide inspector. Templates without a \(device.displayName) layout are flagged until they have one.")
        }
        .confirmationDialog(
            "Remove \(removingDevice?.displayName ?? "")?",
            isPresented: Binding(get: { removingDevice != nil }, set: { if !$0 { removingDevice = nil } }),
            presenting: removingDevice
        ) { device in
            Button("Remove \(device.displayName)", role: .destructive) { coordinator.handle(.removeDevice(device)) }
        } message: { device in
            Text("Its screenshots stop being exported. Templates keep their \(device.displayName) layouts and the slides keep their captures, so adding it back restores them.")
        }
        
        Divider()
        
        InspectorSection("Sizes") {
            ForEach(project.devices, id: \.self) { device in
                InspectorRow(device.displayName) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(DeviceTable.standard.targets(in: device)) { target in
                            Toggle(isOn: Binding(get: { project.targets.contains(target.id) }, set: { on in
                                let targets = on ? project.targets + [target.id] : project.targets.filter { $0 != target.id }
                                coordinator.handle(.setTargets(targets))
                            })) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(target.name + (target.isRequired ? " *" : ""))
                                    Text("\(target.exportSize.width) × \(target.exportSize.height)")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            
            Text("* Required by App Store Connect")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        
        Divider()
        
        if coordinator.document.kind == .project, let set = coordinator.currentSet, set.id != ShotSet.mainID {
            InspectorSection("Custom Product Page") {
                InspectorRow("Name") {
                    TextField("Name", text: Binding(get: { set.name }, set: { coordinator.handle(.renameSet(set.id, $0)) }))
                        .labelsHidden()
                }
                
                InspectorRow("Page ID") {
                    TextField("Page ID", text: Binding(get: { set.customProductPageID ?? "" }, set: { coordinator.handle(.setCustomProductPage(set.id, $0)) }), prompt: Text("From App Store Connect"))
                        .labelsHidden()
                        .help("The custom product page's ID from App Store Connect")
                }
            }
            
            Divider()
        }
        
        if coordinator.document.kind == .project {
            InspectorSection("Project") {
                InspectorRow("Name") {
                    TextField("Name", text: Binding(get: { project.name }, set: { coordinator.handle(.renameProject($0)) }))
                        .labelsHidden()
                }
                
                InspectorRow("Bundle ID") {
                    TextField("com.example.App", text: Binding(get: { project.bundleID ?? "" }, set: { coordinator.handle(.setBundleID($0)) }))
                        .labelsHidden()
                }
            }
            
            Divider()
        }
        
        InspectorSection("Locales") {
            InspectorRow("Source") {
                TextField("en-US", text: Binding(get: { project.sourceLocale }, set: { source in
                    coordinator.handle(.setLocales(source: source, listing: project.listingLocales, app: project.appLocales))
                }))
                .labelsHidden()
            }
            
            InspectorRow("Listing") {
                TextField("en-US, de-DE", text: Binding(get: { project.listingLocales.joined(separator: ", ") }, set: { text in
                    coordinator.handle(.setLocales(source: project.sourceLocale, listing: Self.split(text), app: project.appLocales))
                }))
                .labelsHidden()
                .help("Exported and uploaded")
            }
            
            InspectorRow("App") {
                TextField("en-US, de", text: Binding(get: { project.appLocales.joined(separator: ", ") }, set: { text in
                    coordinator.handle(.setLocales(source: project.sourceLocale, listing: project.listingLocales, app: Self.split(text)))
                }))
                .labelsHidden()
                .help("Captured and previewed")
            }
            
            Text("Each locale runs the app in this language and region")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
            
            ForEach(project.allLocales, id: \.self) { locale in
                let mapped = project.appLocale(for: locale)
                
                InspectorRow(locale) {
                    HStack(spacing: 6) {
                        TextField("Language", text: Binding(get: { mapped.language }, set: { language in
                            coordinator.handle(.setLocaleMapping(locale, AppLocale(language: language, region: mapped.region)))
                        }))
                        .labelsHidden()
                        
                        TextField("Region", text: Binding(get: { mapped.region ?? "" }, set: { region in
                            coordinator.handle(.setLocaleMapping(locale, AppLocale(language: mapped.language, region: region.isEmpty ? nil : region)))
                        }))
                        .labelsHidden()
                    }
                } badge: {
                    if project.localeMap[locale] != nil {
                        Button {
                            coordinator.handle(.setLocaleMapping(locale, nil))
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Use \(locale) as it is")
                        .help("Use \(locale) as it is")
                    }
                }
            }
            
            InspectorRow("Strings") {
                HStack {
                    Button("Export…") { isExportingStrings = true }
                        .fileImporter(isPresented: $isExportingStrings, allowedContentTypes: [.folder]) { result in
                            if case let .success(folder) = result {
                                let accessing = folder.startAccessingSecurityScopedResource()
                                coordinator.exportStrings(to: folder)
                                
                                if accessing {
                                    folder.stopAccessingSecurityScopedResource()
                                }
                            }
                        }
                    
                    Button("Import…") { isImportingStrings = true }
                        .fileImporter(isPresented: $isImportingStrings, allowedContentTypes: [UTType(filenameExtension: "xcstrings") ?? .json, .json]) { result in
                            if case let .success(url) = result, let file = DroppedFile.load(from: [url]).first {
                                coordinator.handle(.importStrings(file))
                            }
                        }
                }
                .help("Marketing text as a String Catalog, translated like the app's strings")
            }
        }
        
        Divider()
        
        InspectorSection("Fonts") {
            ForEach(coordinator.document.fonts.keys.sorted(), id: \.self) { name in
                InspectorRow("") {
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } badge: {
                    Button {
                        coordinator.handle(.removeFont(name))
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(name)")
                }
            }
            
            InspectorRow("") {
                Button("Add Font File…") { isImportingFonts = true }
                    .fileImporter(isPresented: $isImportingFonts, allowedContentTypes: [.font], allowsMultipleSelection: true) { result in
                        if case let .success(urls) = result {
                            coordinator.handle(.addFonts(DroppedFile.load(from: urls)))
                        }
                    }
            }
            
            Text("Fonts chosen in the Template Set tab are embedded too, so renders don't depend on what's installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        
        #if os(macOS)
        if coordinator.document.kind == .project {
            Divider()
            
            InspectorSection("App") {
                if let link = project.appLink {
                    InspectorRow("Project") { Text(URL(filePath: link.projectPath).lastPathComponent) }
                    InspectorRow("Scheme") { Text(link.scheme) }
                    InspectorRow("Test Target") { Text(link.testTarget) }
                } else {
                    Text("Link the app's Xcode project to run its screenshot tests.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                
                InspectorRow("") {
                    Button(project.appLink == nil ? "Link App…" : "Change Link…") { coordinator.handle(.present(.appLink)) }
                }
            }
        }
        #endif
    }
    
    static func symbol(for device: DeviceClass) -> String {
        switch device {
        case .phone: "iphone"
        case .duoOuter, .duoInner: "iphone.gen3"
        case .pad: "ipad"
        case .watch: "applewatch"
        case .mac: "macbook"
        }
    }
    
    private static func split(_ text: String) -> [LocaleID] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            ProjectInspector(coordinator: coordinator)
        }
        .padding()
    }
    .frame(width: 340, height: 900)
}
