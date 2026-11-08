import CoreGraphics
import Dependencies
import Foundation
import Observation
import OSLog
import StagehandModel

/// The document's coordinator: what's selected, every edit (each with undo), and access to rendered scenes.
@Observable
@MainActor
public final class ProjectCoordinator {
    public enum Mode: Hashable, Sendable {
        case contactSheet
        case canvas
    }
    
    /// A sheet or panel the window shows.
    public enum Presentation: String, Hashable, Sendable, Identifiable {
        case export
        case appLink
        case issues
        case runLog
        case upload
        case merge
        case newProjectFromThis
        case importScreenshots
        case searchPreview
        
        public var id: String {
            rawValue
        }
    }
    
    public enum Intent {
        case present(Presentation?)
        
        // Selection
        case selectSet(ShotSet.ID)
        case selectCell(CellID)
        case selectTarget(DeviceTarget.ID)
        case selectLocale(LocaleID)
        case showContactSheet
        case showCanvas
        
        // Slides
        /// A new slide from a template (the first one when `nil`), at an index in the current lineup or at its end.
        case addSlide(template: TemplateID? = nil, at: Int? = nil)
        case duplicateSlide
        case removeSlideFromSet(Slide.ID)
        case deleteDraft(Slide.ID)
        case addDraftToSet(Slide.ID)
        case moveSlides(IndexSet, to: Int)
        case renameSlide(Slide.ID, String)
        case makeIndependentCopy(Slide.ID)
        
        // The selected slide, for the selected device class and locale
        case setText(TextRole, String)
        case overrideText(TextRole)
        case revertText(TextRole)
        case editSlide(String, (inout Slide, DeviceClass) -> Void)
        
        /// The current slide's template on the current class, or on every class sharing the base.
        case setSlideTemplate(TemplateID, scope: EditScope = .automatic)
        case setSlideOn(Slide.ID, DeviceClass, Bool)
        case setExtraText(ElementID, String)
        case setExtraCapture(ElementID, String)
        case setExtraImage(ElementID, DroppedFile)
        
        /// The canvas tried to move a slide's element that follows its template: asks the user first.
        case requestDetach(ElementRef)
        case cancelDetach
        
        /// Copies an element's placement into the current slide's detachment on the current class.
        case detach(ElementRef)
        
        /// Gives an element (or, with `nil`, every element) back to the template on the current class.
        case reattach(ElementRef?)
        
        // Templates
        case selectTemplate(TemplateID?)
        
        /// A new template: a copy of one, or a blank one with a layout for every device in the project.
        case addTemplate(duplicating: TemplateID?)
        case renameTemplate(TemplateID, String)
        case deleteTemplate(TemplateID)
        case moveTemplates(IndexSet, to: Int)
        
        /// Gives the current template a layout for a class: a copy of another class's, or a blank one.
        case addTemplateLayout(DeviceClass, from: DeviceClass?)
        case removeTemplateLayout(DeviceClass)
        
        /// Edits the current template, passing the current class.
        case editTemplate(String, (inout Template, DeviceClass) -> Void)
        
        /// A template's placeholder text, which its editor shows and new slides start with.
        case setPlaceholder(TemplateID, TextRole, String)
        case addElement(TemplateElement.Kind)
        case removeElement(ElementID)
        
        /// Shows or hides an element on the current template's layout for the current class.
        case setElementShown(ElementRef, Bool)
        
        /// A device element's bezel on the current template's layout for the current class.
        case setBezel(ElementRef, BezelChoice)
        
        // The style
        case editStyle(String, (inout Style, DeviceClass) -> Void)
        case renameProject(String)
        case setBundleID(String)
        
        // Sets
        // Devices and lineups
        case addDevice(DeviceClass, includeExistingSlides: Bool)
        case removeDevice(DeviceClass)
        case setTargets([DeviceTarget.ID])
        case addProductPage(name: String)
        case renameSet(ShotSet.ID, String)
        case deleteSet(ShotSet.ID)
        case setCustomProductPage(ShotSet.ID, String)
        
        // Locales
        case setLocales(source: LocaleID, listing: [LocaleID], app: [LocaleID])
        case setLocaleMapping(LocaleID, AppLocale?)
        case importStrings(DroppedFile)
        
        // Captures and fonts
        case importCaptures([DroppedFile], CaptureImporter.Destination)
        
        /// Dropped on the canvas: the selected slide's capture for the device class it's showing. Nothing happens in
        /// the template editor, which has no slide of its own.
        case importCapturesToCanvas([DroppedFile])
        
        /// Every screenshot in a folder and its subfolders (like FlaskMaster's `AppStoreScreenshots/` or TrekPoint's
        /// `Source Images/`), keyed by file name. Ones no slide uses yet are kept, to choose in a slide's Capture Key.
        case importScreenshotsFolder(URL)
        case removeCapture(CaptureAddress)
        case undoQuirk(CaptureAddress, quirkID: String)
        case dismissImportIssues
        case addFonts([DroppedFile])
        case removeFont(String)
        
        /// Uses a font for a text role on the selected class, embedding the installed font's file if it isn't yet.
        case useFont(TextRole, FontSpec)
        
        // Gestures: everything between begin and end is one undo step
        case beginGesture(String)
        case endGesture
        
        // The library
        case saveStyleToLibrary(asNewVersion: Bool)
        case checkForBaseUpdate
        case prepareMerge
        case applyMerge([String: StyleMerge.Side])
        case cancelMerge
        
        case setAppLink(AppLink?)
        case reloadBezels
        case documentReloaded
        case dismissAlert
    }
    
    // MARK: - State
    
    public let document: any EditableDocument
    public internal(set) var selection: EditorSelection
    public internal(set) var mode: Mode = .contactSheet
    
    /// An element the canvas tried to move on a slide that follows its template there, waiting for the user's choice.
    public internal(set) var pendingDetach: ElementRef?
    
    /// Ends whatever edit a text field still has in progress, so it lands on what's selected now. The app sets it (on
    /// the Mac, by ending the field editor's editing), and it runs before every intent that changes the selection.
    ///
    /// A number field commits when it loses focus. Without this, clicking another template, slide or element moved
    /// the focus after the selection had changed, and the typed value landed on the newly selected one.
    @ObservationIgnored public var commitPendingEdits: () -> Void = {}
    public private(set) var fontsReady = false
    public private(set) var fontNames: [String] = []
    /// The library's bezels, with the document's embedded ones laid over them.
    public var bezels: BezelCatalog {
        libraryBezels.merging(embedded: document.contents.bezels)
    }
    
    public internal(set) var libraryBezels: BezelCatalog = .empty
    public private(set) var importIssues: [CaptureImportError] = []
    public var presentation: Presentation?
    public var alert: CoordinatorAlert?
    
    /// The library's newer version of the style this project's came from.
    public private(set) var baseUpdate: LibraryStyle?
    
    /// A merge waiting for its conflicts to be picked.
    public private(set) var pendingMerge: PendingMerge?
    
    /// What the last library action did, for a line in the inspector.
    public private(set) var libraryMessage: String?
    
    public struct PendingMerge: Hashable, Sendable {
        public var library: Style
        public var result: StyleMerge.Result
    }
    
    /// Set by the view from its environment. Every edit registers undo here, which is also how SwiftUI knows to autosave.
    @ObservationIgnored public weak var undoManager: UndoManager?
    
    @ObservationIgnored @Dependency(\.fontRegistry) private var fontRegistry
    @ObservationIgnored @Dependency(\.ubiquity) private var ubiquity
    @ObservationIgnored @Dependency(\.fileManager) private var fileManager
    @ObservationIgnored @Dependency(\.clock) private var clock
    
    @ObservationIgnored private var gesture: (name: String, start: ProjectContents)?
    @ObservationIgnored var bezelLibrary: BezelLibrary?
    @ObservationIgnored public let thumbnails = ThumbnailCache()
    @ObservationIgnored public private(set) lazy var imageStore = ImageStore { [weak self] ref in
        self?.loadImage(ref)
    }
    @ObservationIgnored let autoFit: AutoFitCache
    @ObservationIgnored private let measurer: any TextMeasurer
    @ObservationIgnored private var fontTask: Task<Void, Never>?
    @ObservationIgnored var assetSizeCache: [String: (byteCount: Int, size: CGSize)] = [:]
    
    public init(document: any EditableDocument, measurer: (any TextMeasurer)? = nil) {
        let measurer = measurer ?? SwiftUITextMeasurer()
        self.document = document
        self.measurer = measurer
        self.autoFit = AutoFitCache(measurer: measurer)
        self.selection = EditorSelection(locale: document.project.sourceLocale)
        repairSelection()
        
        // NOTE: - A project with no slides yet (a new one) opens on its first template, ready to design.
        if document.kind == .project, document.project.slides.isEmpty, let first = document.project.style.templates.first {
            selectTemplate(first.id)
        }
    }
    
    /// Registers the document's fonts and loads the bezel library. Rendering waits for fonts.
    public func start() async {
        registerFonts()
        await loadBezels()
        await checkForBaseUpdate()
        await fontTask?.value
    }
    
    // MARK: - Computed Properties
    
    public var project: Project {
        document.project
    }
    
    public var currentSet: ShotSet? {
        selection.setID.flatMap(project.set(id:))
    }
    
    public var currentSlide: Slide? {
        selection.slideID.flatMap { project.slides[$0] }
    }
    
    /// The template being edited, when the template editor is showing.
    public var currentTemplate: Template? {
        selection.templateID.flatMap(project.style.template)
    }
    
    public var currentTarget: DeviceTarget? {
        selection.targetID.flatMap(DeviceTable.standard.target(id:))
    }
    
    public var currentDeviceClass: DeviceClass {
        currentTarget?.deviceClass ?? currentSet?.devices.first ?? .phone
    }
    
    /// The width in pixels of the target the canvas shows (or its class's first target): what a point measures
    /// against. Text sizes are stored as fractions of the canvas's width, so one layout fits every target in a class.
    public var currentCanvasWidth: Double {
        let target = currentTarget ?? DeviceTable.standard.targets(in: currentDeviceClass).first
        return Double(target?.exportSize.width ?? 1)
    }
    
    /// A stored text size (a fraction of the canvas's width) in points on the current target. A point is a pixel of
    /// the export, as in design apps for 72-dpi images like App Store screenshots.
    public func points(fromFraction fraction: Double) -> Double {
        fraction * currentCanvasWidth
    }
    
    public func fraction(fromPoints points: Double) -> Double {
        points / max(currentCanvasWidth, 1)
    }
    
    public var canUndoGesture: Bool {
        gesture != nil
    }
    
    public var contactSheet: ContactSheetState {
        let set = currentSet
        let targets = set?.resolvedTargets() ?? []
        let groups = (set?.devices ?? []).compactMap { device -> ContactSheetState.Group? in
            let columns = targets.filter { $0.deviceClass == device }.map { ContactSheetState.Column(target: $0) }
            return columns.isEmpty ? nil : ContactSheetState.Group(deviceClass: device, columns: columns)
        }
        let rows = set.map { set in
            project.slides(in: set).enumerated().map { index, slide in
                ContactSheetState.Row(
                    slideID: slide.id,
                    number: index + 1,
                    title: slide.title,
                    alsoIn: project.sets(containing: slide.id).filter { $0.id != set.id }.map(\.name),
                    excludedDevices: slide.excludedDevices
                )
            }
        } ?? []
        
        return ContactSheetState(setID: set?.id, groups: groups, rows: rows, locale: selection.locale, locales: project.allLocales)
    }
    
    /// Every flagged cell in every set, then the set-level checks.
    public var issues: [Issue] {
        var issues: [Issue] = []
        
        for set in project.sets {
            for target in set.resolvedTargets() {
                for slide in project.slides(in: set, on: target.deviceClass) {
                    let cell = CellID(setID: set.id, slideID: slide.id, targetID: target.id)
                    
                    for flag in scene(for: cell)?.flags ?? [] where flag.severity > .info {
                        issues.append(Issue(
                            kind: .cell(flag),
                            severity: flag.severity,
                            message: "\(set.name) › \(slide.title) › \(target.name): \(flag.message)",
                            setID: set.id,
                            cell: cell
                        ))
                    }
                }
            }
        }
        
        issues += ProjectValidator.setIssues(project: project, captures: document.captures)
        issues += bezelIssues
        issues += importIssues.map { Issue(kind: .importRefused($0.fileName), severity: .error, message: $0.errorDescription ?? "") }
        return issues
    }
    
    // MARK: - Rendering
    
    public var captureCatalog: CaptureCatalog {
        CaptureCatalog(index: document.captures)
    }
    
    /// The fitted text sizes for a lineup, device class and locale, measured on the class's first target in the
    /// lineup, over the slides that are on that device.
    ///
    /// - Parameter including: A slide to fit as if it were on the device, when it's shown there while it's off (on
    ///   the canvas). Without it, an off slide was drawn at the template set's full size, unfitted.
    public func fitted(set: ShotSet, deviceClass: DeviceClass, locale: LocaleID, including: Slide.ID? = nil) -> AutoFitResult {
        let target = set.resolvedTargets().first { $0.deviceClass == deviceClass }
            ?? DeviceTable.standard.targets(in: deviceClass).first!
        var slides = project.slides(in: set, on: deviceClass)
        
        if let including, !slides.contains(where: { $0.id == including }), let slide = project.slides[including] {
            slides.append(slide)
        }
        
        return autoFit.result(
            slides: slides,
            style: project.style,
            target: target,
            locale: locale,
            sourceLocale: project.sourceLocale
        )
    }
    
    /// The capture keys there are screenshots for on a device class (in any locale), for choosing a slide's: a run
    /// keys each screenshot by its test's name for it, and `inUse` says which a slide already shows.
    public func captureKeys(on device: DeviceClass) -> [(key: String, inUse: Bool)] {
        let captured = Set(document.captures.records.keys.filter { $0.deviceClass == device }.map(\.key))
        let used = Set(project.slides.values.map { $0.captureKey[device] })
        return captured.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { ($0, used.contains($0)) }
    }
    
    /// Why the selected slide's text is smaller than the template set's size, for the inspector: the percentage it's
    /// drawn at, and the slide whose text made it shrink (this one, or the lineup's longest).
    public func textShrinking(_ role: TextRole) -> (percent: Int, cause: Slide)? {
        guard !isEditingTemplate, let set = currentSet, let slide = currentSlide else {
            return nil
        }
        
        let result = fitted(set: set, deviceClass: currentDeviceClass, locale: selection.locale, including: slide.id)
        
        guard let shrinking = result.shrinking(role, on: slide.id), let cause = project.slides[shrinking.cause] else {
            return nil
        }
        
        return (Int((shrinking.fraction * 100).rounded()), cause)
    }
    
    /// A cell's scene in a locale (the selected one by default), at the target's export size unless a canvas is given.
    public func scene(for cell: CellID, locale: LocaleID? = nil, canvas: CGSize? = nil) -> ResolvedScene? {
        guard let set = project.set(id: cell.setID),
              let slide = project.slides[cell.slideID],
              let target = DeviceTable.standard.target(id: cell.targetID) else {
            return nil
        }
        
        let locale = locale ?? selection.locale
        let fitted = fitted(set: set, deviceClass: target.deviceClass, locale: locale, including: slide.id).fitted(for: slide.id)
        
        return Resolver.resolve(ResolveRequest(
            slide: slide,
            style: project.style,
            target: target,
            locale: locale,
            sourceLocale: project.sourceLocale,
            captures: captureCatalog,
            bezels: bezels,
            fitted: fitted,
            lineHeights: lineHeights,
            canvas: canvas,
            assets: assetSizes
        ))
    }
    
    /// Every font installed on the system, by family.
    public var systemFontFamilies: [FontFamily] {
        fontRegistry.availableFamilies()
    }
    
    /// Each of the style's fonts' line heights, measured the way text renders.
    public var lineHeights: [FontSpec: Double] {
        Dictionary(uniqueKeysWithValues: project.style.fonts.map { ($0, measurer.lineHeight(for: $0)) })
    }
    
    public func images(for scene: ResolvedScene) -> SceneImages {
        imageStore.images(for: scene)
    }
    
    /// A cell's cached thumbnail at a width in pixels.
    public func thumbnail(for cell: CellID, width: Double) -> CGImage? {
        guard fontsReady, let scene = scene(for: cell) else {
            return nil
        }
        
        return thumbnails.thumbnail(for: scene, scale: width / scene.canvas.width) {
            imageStore.images(for: scene)
        }
    }
    
    public func status(for cell: CellID) -> CellStatus {
        CellStatus(flags: scene(for: cell)?.flags ?? [], run: nil)
    }
    
    /// Exports every listing locale's images into a folder.
    @discardableResult
    public func export(to folder: URL) -> [URL] {
        let exporter = ProjectExporter()
        let items = exporter.items(for: project)
        
        do {
            let urls = try exporter.export(items, to: folder, fileManager: fileManager) { item throws(ExportError) in
                guard let scene = scene(for: CellID(setID: item.setID, slideID: item.slideID, targetID: item.target.id), locale: item.locale) else {
                    throw .renderFailed(item.relativePath)
                }
                
                return try SceneRenderer.exportPNG(scene, images: images(for: scene), name: item.relativePath)
            }
            
            Logger.export.info("Exported \(urls.count) images to \(folder.path(percentEncoded: false), privacy: .public)")
            return urls
        } catch {
            Logger.export.error("Export failed: \(error.localizedDescription, privacy: .public)")
            alert = CoordinatorAlert(title: "Export Failed", error: error)
            return []
        }
    }
    
    /// A new project carrying this one's template set and devices (always), and optionally its slide skeleton (the
    /// slides, their order, templates and capture keys) and text. Captures and the app link stay behind, since they
    /// belong to this app.
    public func derivedProject(name: String, carrySkeleton: Bool, carryText: Bool) -> ProjectContents {
        let source = project
        var derived = Project(
            name: name,
            style: source.style,
            basedOn: source.basedOn,
            devices: source.devices,
            targets: source.targets,
            sourceLocale: source.sourceLocale,
            listingLocales: source.listingLocales,
            appLocales: source.appLocales,
            localeMap: source.localeMap
        )
        
        if carrySkeleton {
            for id in source.slideOrder {
                guard var copy = source.slides[id] else {
                    continue
                }
                
                copy.id = UUID()
                copy.detachments = [:]
                
                if !carryText {
                    copy.primary = Varying([source.sourceLocale: "Headline"])
                    copy.secondary = Varying([source.sourceLocale: "A line about this screen"])
                }
                
                derived.slides[copy.id] = copy
                derived.slideOrder.append(copy.id)
            }
        }
        
        var contents = ProjectContents(project: derived, fonts: document.fonts)
        contents.bezels = document.contents.bezels
        return contents
    }
    
    /// Writes the marketing text as `<project name> Marketing.xcstrings` into a folder.
    @discardableResult
    public func exportStrings(to folder: URL) -> URL? {
        let url = folder.appending(path: "\(project.name) Marketing.xcstrings")
        
        do {
            try fileManager.write(try StringCatalog.export(project), to: url)
            return url
        } catch {
            alert = CoordinatorAlert(title: "Couldn't Export Strings", error: error)
            return nil
        }
    }
    
    // MARK: - Intents
    
    public func handle(_ intent: Intent) {
        if intent.changesSelection {
            commitPendingEdits()
        }
        
        switch intent {
        case let .present(presentation):
            self.presentation = presentation
        case let .selectSet(id):
            selection.setID = id
            repairSelection()
        case let .selectCell(cell):
            selection.setID = cell.setID
            selection.slideID = cell.slideID
            selection.targetID = cell.targetID
            selection.templateID = nil
            mode = .canvas
        case let .selectTarget(id):
            selection.targetID = id
        case let .selectLocale(locale):
            selection.locale = locale
        case .showContactSheet:
            mode = .contactSheet
        case .showCanvas:
            repairSelection()
            mode = .canvas
        
        case let .addSlide(template, index):
            addSlide(template: template, at: index)
        case .duplicateSlide:
            duplicateSlide()
        case let .removeSlideFromSet(id):
            guard let setID = selection.setID else { return }
            edit("Remove Slide") { contents in
                contents.project.updateSet(id: setID) { $0.slideIDs.removeAll { $0 == id } }
            }
            repairSelection()
        case let .deleteDraft(id):
            edit("Delete Slide") { $0.project.deleteSlide(id) }
            repairSelection()
        case let .addDraftToSet(id):
            guard let setID = selection.setID else { return }
            edit("Add Slide to Set") { contents in
                contents.project.updateSet(id: setID) { set in
                    if !set.slideIDs.contains(id) {
                        set.slideIDs.append(id)
                    }
                }
            }
        case let .moveSlides(offsets, destination):
            guard let setID = selection.setID else { return }
            edit("Reorder Slides") { contents in
                contents.project.updateSet(id: setID) { $0.slideIDs.move(fromOffsets: offsets, toOffset: destination) }
            }
        case let .renameSlide(id, title):
            edit("Rename Slide") { $0.project.slides[id]?.title = title }
        case let .makeIndependentCopy(id):
            makeIndependentCopy(id)
        
        case let .setText(role, text):
            editCurrentSlide("Edit Text") { slide, device, locale in
                slide.updateText(role) { $0.setText(text, for: device, locale: locale) }
            }
        case let .overrideText(role):
            let source = project.sourceLocale
            editCurrentSlide("Override Text") { slide, device, locale in
                slide.updateText(role) { $0.overrideText(for: device, locale: locale, source: source) }
            }
        case let .revertText(role):
            editCurrentSlide("Revert to Shared") { slide, device, locale in
                slide.updateText(role) { $0.revertText(for: device, locale: locale) }
            }
        case let .editSlide(name, body):
            editCurrentSlide(name) { slide, device, _ in body(&slide, device) }
        case let .setSlideTemplate(id, scope):
            editCurrentSlide("Change Template") { slide, device, _ in slide.setTemplate(id, for: device, scope: scope) }
        case let .setSlideOn(id, device, isOn):
            edit(isOn ? "Show Slide on \(device.displayName)" : "Hide Slide on \(device.displayName)") { $0.project.slides[id]?.setOn(device, isOn) }
        case let .setExtraText(element, text):
            setExtraText(element, text)
        case let .setExtraCapture(element, key):
            setExtraCapture(element, key)
        case let .setExtraImage(element, file):
            setExtraImage(element, file)
        case let .requestDetach(element):
            pendingDetach = element
        case .cancelDetach:
            pendingDetach = nil
        case let .detach(element):
            detach(element)
        case let .reattach(element):
            reattach(element)
        
        case let .selectTemplate(id):
            selectTemplate(id)
        case let .addTemplate(source):
            addTemplate(duplicating: source)
        case let .renameTemplate(id, name):
            edit("Rename Template") { $0.project.style.updateTemplate(id) { $0.name = name } }
        case let .deleteTemplate(id):
            deleteTemplate(id)
        case let .moveTemplates(offsets, destination):
            edit("Reorder Templates") { $0.project.style.templates.move(fromOffsets: offsets, toOffset: destination) }
        case let .addTemplateLayout(device, source):
            addTemplateLayout(device, from: source)
        case let .removeTemplateLayout(device):
            guard let id = selection.templateID else { return }
            edit("Remove \(device.displayName) Layout") { $0.project.style.updateTemplate(id) { $0.layouts[device] = nil } }
        case let .setPlaceholder(id, role, text):
            edit("Change Placeholder") { contents in
                contents.project.style.updateTemplate(id) { template in
                    switch role {
                    case .primary: template.placeholder.primary = text
                    case .secondary: template.placeholder.secondary = text
                    }
                }
            }
        case let .editTemplate(name, body):
            guard let id = selection.templateID else { return }
            let device = currentDeviceClass
            edit(name) { $0.project.style.updateTemplate(id) { body(&$0, device) } }
        case let .addElement(kind):
            addElement(kind)
        case let .removeElement(element):
            removeElement(element)
        case let .setElementShown(element, isShown):
            setElementShown(element, isShown)
        case let .setBezel(element, choice):
            setBezel(element, choice)
        
        case let .editStyle(name, body):
            let device = currentDeviceClass
            edit(name) { body(&$0.project.style, device) }
        case let .renameProject(name):
            edit("Rename Project") { $0.project.name = name }
        case let .setBundleID(bundleID):
            edit("Change Bundle Identifier") { $0.project.bundleID = bundleID.isEmpty ? nil : bundleID }
        
        case let .addDevice(device, includeExistingSlides):
            addDevice(device, includeExistingSlides: includeExistingSlides)
        case let .removeDevice(device):
            edit("Remove \(device.displayName)") { $0.project.removeDevice(device) }
            repairSelection()
        case let .setTargets(targets):
            edit("Change Sizes") { $0.project.targets = targets }
            repairSelection()
        case let .addProductPage(name):
            let page = ProductPage(name: name, slideIDs: project.slideOrder)
            edit("Add Custom Product Page") { $0.project.productPages.append(page) }
            selection.setID = page.id
            repairSelection()
        case let .renameSet(id, name):
            edit("Rename Custom Product Page") { $0.project.updateSet(id: id) { $0.name = name } }
        case let .deleteSet(id):
            edit("Delete Custom Product Page") { $0.project.productPages.removeAll { $0.id == id } }
            repairSelection()
        case let .setCustomProductPage(id, pageID):
            let trimmed = pageID.trimmingCharacters(in: .whitespaces)
            edit("Change Custom Product Page") { $0.project.updateSet(id: id) { $0.customProductPageID = trimmed.isEmpty ? nil : trimmed } }
        
        case let .setLocales(source, listing, app):
            edit("Change Locales") { contents in
                contents.project.sourceLocale = source
                contents.project.listingLocales = listing
                contents.project.appLocales = app
            }
            
            if !project.allLocales.contains(selection.locale) {
                selection.locale = source
            }
        case let .setLocaleMapping(locale, appLocale):
            edit("Change Locale Map") { $0.project.localeMap[locale] = appLocale }
        case let .importStrings(file):
            do {
                let imported = try StringCatalog.importCatalog(file.data, into: project)
                edit("Import Strings") { $0.project = imported }
            } catch {
                alert = CoordinatorAlert(title: "Couldn't Import Strings", error: error)
            }
        
        case let .importCaptures(files, destination):
            importCaptures(files, destination: destination)
        case let .importScreenshotsFolder(folder):
            let files = CaptureImporter.imageFiles(in: folder, fileManager: fileManager).compactMap { url in
                (try? fileManager.read(url)).map { DroppedFile(name: url.lastPathComponent, data: $0) }
            }
            
            importCaptures(files, destination: .folder)
        case let .importCapturesToCanvas(files):
            guard !isEditingTemplate, let slide = currentSlide else { return }
            let device = currentDeviceClass
            importCaptures(files, destination: .cell(key: slide.captureKey[device], deviceClass: device))
        case let .removeCapture(address):
            edit("Remove Capture") { contents in
                contents.captures.records[address] = nil
                contents.captureFiles[address] = nil
            }
        case let .undoQuirk(address, quirkID):
            undoQuirk(address, quirkID: quirkID)
        case .dismissImportIssues:
            importIssues = []
        case let .addFonts(files):
            addFonts(files)
        case let .removeFont(name):
            edit("Remove Font") { $0.fonts[name] = nil }
        case let .useFont(role, font):
            useFont(font, for: role)
        
        case let .beginGesture(name):
            if gesture == nil {
                gesture = (name, document.contents)
            }
        case .endGesture:
            endGesture()
        
        case let .saveStyleToLibrary(asNewVersion):
            Task { await saveStyleToLibrary(asNewVersion: asNewVersion) }
        case .checkForBaseUpdate:
            Task { await checkForBaseUpdate() }
        case .prepareMerge:
            Task { await prepareMerge() }
        case let .applyMerge(resolutions):
            applyMerge(resolutions)
        case .cancelMerge:
            pendingMerge = nil
            presentation = nil
        
        case let .setAppLink(link):
            edit("Change App Link") { $0.project.appLink = link }
        case .reloadBezels:
            Task { await loadBezels() }
        case .documentReloaded:
            thumbnails.removeAll()
            imageStore.invalidate()
            autoFit.removeAll()
            repairSelection()
            registerFonts()
        case .dismissAlert:
            alert = nil
        }
    }
    
    // MARK: - Editing
    
    /// Changes the document, registering one undo step for it (or folding it into the current gesture's).
    public func edit(_ name: String, _ body: (inout ProjectContents) -> Void) {
        let before = document.contents
        var after = before
        body(&after)
        
        guard after != before else {
            return
        }
        
        document.contents = after
        
        if gesture == nil {
            registerUndo(restoring: before, name: name)
        }
    }
    
    func editCurrentSlide(_ name: String, _ body: (inout Slide, DeviceClass, LocaleID) -> Void) {
        guard let id = selection.slideID else {
            return
        }
        
        let device = currentDeviceClass
        let locale = selection.locale
        
        edit(name) { contents in
            guard var slide = contents.project.slides[id] else {
                return
            }
            
            body(&slide, device, locale)
            contents.project.slides[id] = slide
        }
    }
    
    private func endGesture() {
        guard let gesture else {
            return
        }
        
        self.gesture = nil
        
        if document.contents != gesture.start {
            registerUndo(restoring: gesture.start, name: gesture.name)
        }
    }
    
    private func registerUndo(restoring contents: ProjectContents, name: String) {
        guard let undoManager else {
            return
        }
        
        let isReplaying = undoManager.isUndoing || undoManager.isRedoing
        
        if !isReplaying {
            undoManager.beginUndoGrouping()
        }
        
        undoManager.registerUndo(withTarget: self) { coordinator in
            MainActor.assumeIsolated {
                coordinator.restore(contents, name: name)
            }
        }
        
        undoManager.setActionName(name)
        
        if !isReplaying {
            undoManager.endUndoGrouping()
        }
    }
    
    private func restore(_ contents: ProjectContents, name: String) {
        let current = document.contents
        let fontsChanged = current.fonts != contents.fonts
        document.contents = contents
        registerUndo(restoring: current, name: name)
        repairSelection()
        
        if fontsChanged {
            registerFonts()
        }
    }
    
    // MARK: - Helpers
    
    /// Keeps the selection pointing at things that exist.
    func repairSelection() {
        let project = document.project
        
        if selection.setID.flatMap(project.set(id:)) == nil {
            selection.setID = project.sets.first?.id
        }
        
        let set = selection.setID.flatMap(project.set(id:))
        
        if let slideID = selection.slideID, project.slides[slideID] != nil, set?.slideIDs.contains(slideID) ?? false {
            // Still valid.
        } else if let slideID = selection.slideID, project.slides[slideID] != nil, set == nil {
            // A draft, with no set.
        } else {
            selection.slideID = set?.slideIDs.first
        }
        
        let targets = set?.resolvedTargets() ?? []
        
        if !targets.contains(where: { $0.id == selection.targetID }) {
            selection.targetID = targets.first?.id
        }
        
        if !project.allLocales.contains(selection.locale) {
            selection.locale = project.sourceLocale
        }
        
        if let templateID = selection.templateID, project.style.template(templateID) == nil {
            selection.templateID = nil
        }
    }
    
    private func duplicateSlide() {
        guard let setID = selection.setID, let original = currentSlide else {
            return
        }
        
        var copy = original
        copy.id = UUID()
        copy.title = original.title + " Copy"
        
        edit("Duplicate Slide") { contents in
            contents.project.slides[copy.id] = copy
            contents.project.updateSet(id: setID) { set in
                let index = set.slideIDs.firstIndex(of: original.id).map { $0 + 1 } ?? set.slideIDs.count
                set.slideIDs.insert(copy.id, at: index)
            }
        }
        
        selection.slideID = copy.id
    }
    
    /// Splits a shared slide: the current set gets its own copy, and the other sets keep the original.
    private func makeIndependentCopy(_ id: Slide.ID) {
        guard let setID = selection.setID, let original = project.slides[id] else {
            return
        }
        
        var copy = original
        copy.id = UUID()
        
        edit("Make Independent Copy") { contents in
            contents.project.slides[copy.id] = copy
            contents.project.updateSet(id: setID) { set in
                set.slideIDs = set.slideIDs.map { $0 == id ? copy.id : $0 }
            }
        }
        
        if selection.slideID == id {
            selection.slideID = copy.id
        }
    }
    
    private func importCaptures(_ files: [DroppedFile], destination: CaptureImporter.Destination) {
        let now = clock.now
        let locale = selection.locale
        let keys = project.captureKeys
        var refused: [CaptureImportError] = []
        
        edit(files.count == 1 ? "Add Capture" : "Add Captures") { contents in
            for file in files {
                let result = CaptureImporter.importImage(
                    file.data,
                    fileName: file.name,
                    destination: destination,
                    locale: locale,
                    existing: contents.captures,
                    now: now
                )
                
                switch result {
                case let .success(imported) where destination == .sheet && !keys.contains(imported.record.address.key):
                    // NOTE: - Stored, it would belong to no slide and never show, so the drop would seem to do nothing.
                    refused.append(.noMatchingSlide(file.name, key: imported.record.address.key))
                case let .success(imported):
                    contents.captures.records[imported.record.address] = imported.record
                    contents.captureFiles[imported.record.address] = imported.data
                case let .failure(error):
                    refused.append(error)
                }
            }
        }
        
        importIssues += refused
    }
    
    /// Reverses a quirk's fix on import, for a capture from a runtime where Apple fixed the bug.
    private func undoQuirk(_ address: CaptureAddress, quirkID: String) {
        guard let quirk = Quirk.all.first(where: { $0.id == quirkID }),
              let data = document.captureFiles[address],
              let image = CGImage.decode(data) else {
            return
        }
        
        let fixed: CGImage? = switch quirk.fix.inverse {
        case .rotate180: image.rotated180()
        }
        
        guard let png = fixed?.flattened()?.pngData() else {
            alert = CoordinatorAlert(title: "Couldn't Undo Quirk", message: "The capture couldn't be re-encoded.")
            return
        }
        
        edit("Undo Quirk") { contents in
            contents.captureFiles[address] = png
            contents.captures.records[address]?.revision += 1
            contents.captures.records[address]?.quirksUndone.append(quirkID)
        }
    }
    
    private func addFonts(_ files: [DroppedFile]) {
        let registry = fontRegistry
        var accepted: [String: Data] = [:]
        
        for file in files {
            do {
                _ = try registry.postScriptName(of: file.data, fileName: file.name)
                accepted[file.name] = file.data
            } catch {
                alert = CoordinatorAlert(title: "Couldn't Add Font", error: error)
            }
        }
        
        guard !accepted.isEmpty else {
            return
        }
        
        edit("Add Font") { contents in
            contents.fonts.merge(accepted) { $1 }
        }
        
        registerFonts()
    }
    
    /// The largest font file Stagehand embeds. Some system collections (like the CJK ones) are far larger.
    static let maximumEmbeddedFontSize = 40_000_000
    
    private func useFont(_ font: FontSpec, for role: TextRole) {
        let device = currentDeviceClass
        var embedded: (name: String, data: Data)?
        
        if font.systemWeight == nil, !fontNames.contains(font.postScriptName) {
            guard let url = fontRegistry.fontFile(postScriptName: font.postScriptName),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                alert = CoordinatorAlert(title: "Couldn't Embed Font", message: "\(font.postScriptName)'s file couldn't be read, so it isn't embedded. It renders only where it's installed.")
                return
            }
            
            guard data.count <= Self.maximumEmbeddedFontSize else {
                alert = CoordinatorAlert(title: "Font Too Large", message: "\(url.lastPathComponent) is \(data.count / 1_000_000) MB, too large to embed in the document.")
                return
            }
            
            embedded = (url.lastPathComponent, data)
        }
        
        edit("Change Font") { contents in
            if let embedded {
                contents.fonts[embedded.name] = embedded.data
            }
            
            contents.project.style.updateTextStyle(role) { $0.font.set(font, for: device) }
        }
        
        if embedded != nil {
            registerFonts()
        }
    }
    
    private func registerFonts() {
        let registry = fontRegistry
        let fonts = document.fonts
        fontsReady = false
        
        fontTask = Task { [weak self] in
            do {
                let names = try await registry.register(fonts)
                self?.fontNames = names.sorted()
            } catch {
                Logger.fonts.error("Font registration failed: \(error.localizedDescription, privacy: .public)")
                self?.alert = CoordinatorAlert(title: "Couldn't Load Fonts", error: error)
            }
            
            self?.thumbnails.removeAll()
            self?.autoFit.removeAll()
            self?.fontsReady = true
        }
    }
    
    private func styleLibrary() async -> StyleLibrary {
        let ubiquity = ubiquity
        return StyleLibrary(libraryURL: await ubiquity.libraryURL(), fileManager: fileManager)
    }
    
    private func saveStyleToLibrary(asNewVersion: Bool) async {
        let library = await styleLibrary()
        var style = project.style
        style.name = document.kind == .style ? project.name : style.name
        
        do {
            let base = try library.save(style, fonts: document.fonts, bezels: document.contents.bezels, asNewVersion: asNewVersion)
            
            edit("Save Style to Library") { contents in
                contents.project.basedOn = base
                contents.project.style.id = base.styleID
                contents.project.style.version = base.version
            }
            
            baseUpdate = nil
            libraryMessage = "Saved \(base.snapshot.name) to the library as version \(base.version)."
        } catch {
            alert = CoordinatorAlert(title: "Couldn't Save Style", error: error)
        }
    }
    
    private func checkForBaseUpdate() async {
        guard let base = project.basedOn else {
            baseUpdate = nil
            return
        }
        
        let library = await styleLibrary()
        let current = library.style(id: base.styleID)
        baseUpdate = current.flatMap { $0.version > base.version ? $0 : nil }
    }
    
    private func prepareMerge() async {
        guard let base = project.basedOn, let update = baseUpdate else {
            return
        }
        
        do {
            let library = try await styleLibrary().load(update).project.style
            let result = try StyleMerge.merge(base: base.snapshot, library: library, project: project.style)
            pendingMerge = PendingMerge(library: library, result: result)
            
            if result.conflicts.isEmpty {
                applyMerge([:])
            } else {
                presentation = .merge
            }
        } catch {
            alert = CoordinatorAlert(title: "Couldn't Pull Changes", error: error)
        }
    }
    
    private func applyMerge(_ resolutions: [String: StyleMerge.Side]) {
        guard let pending = pendingMerge, let base = project.basedOn else {
            return
        }
        
        do {
            let result = try StyleMerge.merge(base: base.snapshot, library: pending.library, project: project.style, resolutions: resolutions)
            
            edit("Pull Style Changes") { contents in
                contents.project.style = result.merged
                contents.project.basedOn = BaseStyle(styleID: base.styleID, version: pending.library.version, snapshot: pending.library)
            }
            
            libraryMessage = "Pulled version \(pending.library.version) of \(pending.library.name)."
        } catch {
            alert = CoordinatorAlert(title: "Couldn't Pull Changes", error: error)
        }
        
        pendingMerge = nil
        baseUpdate = nil
        presentation = nil
    }
    
    func loadBezels() async {
        let ubiquity = ubiquity
        let fileManager = fileManager
        let library = BezelLibrary(libraryURL: await ubiquity.libraryURL(), fileManager: fileManager)
        bezelLibrary = library
        libraryBezels = library.load()
        imageStore.invalidate { $0.rawValue.hasPrefix("bezel") }
        thumbnails.removeAll()
    }
    
    private func loadImage(_ ref: ImageRef) -> CGImage? {
        let raw = ref.rawValue
        
        if raw.hasPrefix("capture:") {
            let path = raw.dropFirst("capture:".count).split(separator: "#").first.map(String.init) ?? ""
            let address = document.captures.records.keys.first { $0.relativePath == path }
            return address.flatMap { document.captureFiles[$0] }.flatMap(CGImage.decode)
        }
        
        // A project's embedded copy of a bezel wins over the library's.
        if raw.hasPrefix("bezel-mask:") {
            let id = String(raw.dropFirst("bezel-mask:".count))
            
            if let embedded = document.contents.bezels[id] {
                return CGImage.decode(embedded.png).flatMap { try? BezelDetector.detect(in: $0).mask }
            }
            
            return bezelLibrary?.mask(for: id)
        }
        
        if raw.hasPrefix("bezel:") {
            let id = String(raw.dropFirst("bezel:".count))
            return document.contents.bezels[id].flatMap { CGImage.decode($0.png) } ?? bezelLibrary?.image(for: id)
        }
        
        if raw.hasPrefix("asset:") {
            return document.contents.assets[String(raw.dropFirst("asset:".count))].flatMap(CGImage.decode)
        }
        
        return nil
    }
}

extension Project {
    /// Every capture key a slide uses, on any device class, its extra elements' included.
    var captureKeys: Set<String> {
        var keys = Set<String>()
        
        for slide in slides.values {
            for device in DeviceClass.allCases {
                keys.insert(slide.captureKey[device])
                
                for content in slide.extraContent.values {
                    if let key = content.captureKey?[device] {
                        keys.insert(key)
                    }
                }
            }
        }
        
        return keys
    }
}

extension ProjectCoordinator.Intent {
    /// Whether the intent moves the selection to another template, slide, lineup, target or locale, or another mode,
    /// so a text field's edit in progress has to land first (``ProjectCoordinator/commitPendingEdits``).
    var changesSelection: Bool {
        switch self {
        case .selectSet, .selectCell, .selectTarget, .selectLocale, .showContactSheet, .showCanvas, .selectTemplate,
             .addSlide, .duplicateSlide, .addTemplate, .deleteTemplate, .makeIndependentCopy, .addProductPage:
            true
        default:
            false
        }
    }
}
