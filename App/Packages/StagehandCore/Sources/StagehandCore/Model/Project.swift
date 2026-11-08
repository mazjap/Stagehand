import Foundation
import StagehandModel

/// One app's screenshots.
public struct Project: Codable, Hashable, Sendable {
    /// The format this version of Stagehand writes.
    public static let currentFormatVersion = 3
    
    public var formatVersion: Int
    public var name: String
    
    /// An embedded copy, so the library style never changes underneath shipped screenshots.
    public var style: Style
    public var basedOn: BaseStyle?
    
    /// The devices the project makes screenshots for, in the contact sheet's column order. Added one at a time.
    public var devices: [DeviceClass]
    
    /// The App Store Connect sizes to export, each in one of ``devices``.
    public var targets: [DeviceTarget.ID]
    
    /// The pool. The order and product pages reference slides by ID.
    public var slides: [Slide.ID: Slide]
    
    /// The order on every device, which uploads to the product page. A device skips the slides that are off for it.
    public var slideOrder: [Slide.ID]
    
    /// Custom product pages, each with its own slides and order.
    public var productPages: [ProductPage]
    public var sourceLocale: LocaleID
    
    /// Exported and uploaded.
    public var listingLocales: [LocaleID]
    
    /// Captured and previewed: the app's languages.
    public var appLocales: [LocaleID]
    
    /// Listing locale to the app's language and region.
    public var localeMap: [LocaleID: AppLocale]
    
    /// The Xcode project the runner drives.
    public var appLink: AppLink?
    
    /// The app's bundle identifier, for App Store Connect.
    public var bundleID: String?
    
    public init(
        formatVersion: Int = Project.currentFormatVersion,
        name: String,
        style: Style,
        basedOn: BaseStyle? = nil,
        devices: [DeviceClass] = [.phone],
        targets: [DeviceTarget.ID]? = nil,
        slides: [Slide.ID: Slide] = [:],
        slideOrder: [Slide.ID] = [],
        productPages: [ProductPage] = [],
        sourceLocale: LocaleID = "en-US",
        listingLocales: [LocaleID] = ["en-US"],
        appLocales: [LocaleID] = ["en-US"],
        localeMap: [LocaleID: AppLocale] = [:],
        appLink: AppLink? = nil,
        bundleID: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.style = style
        self.basedOn = basedOn
        self.devices = devices
        self.targets = targets ?? ShotSet.defaultTargets(for: devices)
        self.slides = slides
        self.slideOrder = slideOrder
        self.productPages = productPages
        self.sourceLocale = sourceLocale
        self.listingLocales = listingLocales
        self.appLocales = appLocales
        self.localeMap = localeMap
        self.appLink = appLink
        self.bundleID = bundleID
    }
    
    // MARK: - Coding
    
    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case name
        case style
        case basedOn
        case devices
        case targets
        case slides
        case slideOrder
        case productPages
        case sourceLocale
        case listingLocales
        case appLocales
        case localeMap
        case appLink
        case bundleID
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        self.name = try container.decode(String.self, forKey: .name)
        self.style = try container.decode(Style.self, forKey: .style)
        self.basedOn = try container.decodeIfPresent(BaseStyle.self, forKey: .basedOn)
        self.devices = try container.decode([DeviceClass].self, forKey: .devices)
        self.targets = try container.decode([DeviceTarget.ID].self, forKey: .targets)
        self.slideOrder = try container.decode([Slide.ID].self, forKey: .slideOrder)
        self.productPages = try container.decodeIfPresent([ProductPage].self, forKey: .productPages) ?? []
        self.sourceLocale = try container.decode(LocaleID.self, forKey: .sourceLocale)
        self.listingLocales = try container.decode([LocaleID].self, forKey: .listingLocales)
        self.appLocales = try container.decode([LocaleID].self, forKey: .appLocales)
        self.localeMap = try container.decodeIfPresent([LocaleID: AppLocale].self, forKey: .localeMap) ?? [:]
        self.appLink = try container.decodeIfPresent(AppLink.self, forKey: .appLink)
        self.bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        
        // NOTE: - Slides are keyed by their ID's string, since a dictionary keyed by `UUID` encodes as an array.
        let slides = try container.decode([String: Slide].self, forKey: .slides)
        self.slides = Dictionary(slides.values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(name, forKey: .name)
        try container.encode(style, forKey: .style)
        try container.encodeIfPresent(basedOn, forKey: .basedOn)
        try container.encode(devices, forKey: .devices)
        try container.encode(targets, forKey: .targets)
        try container.encode(Dictionary(uniqueKeysWithValues: slides.map { ($0.key.uuidString, $0.value) }), forKey: .slides)
        try container.encode(slideOrder, forKey: .slideOrder)
        try container.encode(productPages, forKey: .productPages)
        try container.encode(sourceLocale, forKey: .sourceLocale)
        try container.encode(listingLocales, forKey: .listingLocales)
        try container.encode(appLocales, forKey: .appLocales)
        try container.encode(localeMap, forKey: .localeMap)
        try container.encodeIfPresent(appLink, forKey: .appLink)
        try container.encodeIfPresent(bundleID, forKey: .bundleID)
    }
    
    // MARK: - Lineups
    
    /// Every lineup: the main one (the project's order, for the product page), then each custom product page.
    ///
    /// Lineups are computed, never saved. Every lineup shows the project's devices and exports its targets.
    public var sets: [ShotSet] {
        [mainLineup] + productPages.map { page in
            ShotSet(id: page.id, name: page.name, devices: devices, targets: targets, slideIDs: page.slideIDs, customProductPageID: page.pageID)
        }
    }
    
    public var mainLineup: ShotSet {
        ShotSet(id: ShotSet.mainID, name: "App Store", devices: devices, targets: targets, slideIDs: slideOrder)
    }
    
    /// The slides of a lineup, in its order.
    public func slides(in set: ShotSet) -> [Slide] {
        set.slideIDs.compactMap { slides[$0] }
    }
    
    /// The slides of a lineup that are on a device, in order.
    public func slides(in set: ShotSet, on device: DeviceClass) -> [Slide] {
        slides(in: set).filter { $0.isOn(device) }
    }
    
    public func set(id: ShotSet.ID) -> ShotSet? {
        sets.first { $0.id == id }
    }
    
    /// Changes a lineup: the main one writes back its slides, devices and targets, and a product page its slides,
    /// name and page ID.
    public mutating func updateSet(id: ShotSet.ID, _ body: (inout ShotSet) -> Void) {
        if id == ShotSet.mainID {
            var set = mainLineup
            body(&set)
            slideOrder = set.slideIDs
            devices = set.devices
            targets = set.targets
        } else if let index = productPages.firstIndex(where: { $0.id == id }) {
            var set = sets[index + 1]
            body(&set)
            productPages[index].slideIDs = set.slideIDs
            productPages[index].name = set.name
            productPages[index].pageID = set.customProductPageID ?? ""
        }
    }
    
    /// Every lineup that references a slide.
    public func sets(containing slideID: Slide.ID) -> [ShotSet] {
        sets.filter { $0.slideIDs.contains(slideID) }
    }
    
    /// Slides no lineup references, which wait in the Drafts tray.
    public var drafts: [Slide] {
        let referenced = Set(slideOrder + productPages.flatMap(\.slideIDs))
        return slides.values.filter { !referenced.contains($0.id) }.sorted { $0.title < $1.title }
    }
    
    /// Removes a slide from the pool, the order and every product page.
    public mutating func deleteSlide(_ id: Slide.ID) {
        slides[id] = nil
        slideOrder.removeAll { $0 == id }
        
        for index in productPages.indices {
            productPages[index].slideIDs.removeAll { $0 == id }
        }
    }
    
    /// Adds a device, with its default targets. Existing slides are on it unless `includeExistingSlides` is off.
    public mutating func addDevice(_ device: DeviceClass, includeExistingSlides: Bool) {
        guard !devices.contains(device) else {
            return
        }
        
        devices.append(device)
        targets += ShotSet.defaultTargets(for: [device])
        
        if !includeExistingSlides {
            for id in slides.keys {
                slides[id]?.setOn(device, false)
            }
        }
    }
    
    /// Removes a device and its targets. Slides keep their captures and text for it.
    public mutating func removeDevice(_ device: DeviceClass) {
        devices.removeAll { $0 == device }
        targets.removeAll { DeviceTable.standard.target(id: $0)?.deviceClass == device }
        
        for id in slides.keys {
            slides[id]?.excludedDevices.remove(device)
        }
    }
    
    // MARK: - Functions
    
    /// Every locale the project shows: the source, then app and listing locales.
    public var allLocales: [LocaleID] {
        var seen = Set<LocaleID>()
        return ([sourceLocale] + appLocales + listingLocales).filter { seen.insert($0).inserted }
    }
    
    /// The app's language and region for a locale, from the locale map or the locale itself.
    public func appLocale(for locale: LocaleID) -> AppLocale {
        localeMap[locale] ?? AppLocale(identifier: locale)
    }
}

/// An App Store Connect custom product page: its own slides, in its own order, on the project's devices.
public struct ProductPage: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    
    /// App Store Connect's ID for the page.
    public var pageID: String
    public var slideIDs: [Slide.ID]
    
    public init(id: UUID = UUID(), name: String, pageID: String = "", slideIDs: [Slide.ID] = []) {
        self.id = id
        self.name = name
        self.pageID = pageID
        self.slideIDs = slideIDs
    }
}

/// The language and region an app runs in, for `-testLanguage` and `-testRegion`.
public struct AppLocale: Codable, Hashable, Sendable {
    public var language: String
    public var region: String?
    
    public init(language: String, region: String?) {
        self.language = language
        self.region = region
    }
    
    /// Splits `de-DE` into `de` and `DE`.
    public init(identifier: LocaleID) {
        let parts = identifier.split(separator: "-", maxSplits: 1).map(String.init)
        self.init(language: parts[0], region: parts.count > 1 ? parts[1] : nil)
    }
}

/// A lineup: an ordered list of slides on the project's devices. The main lineup is the project's order, and each
/// custom product page is another. Computed by ``Project/sets``, never saved (format 2 saved them as sets).
public struct ShotSet: Codable, Hashable, Sendable, Identifiable {
    /// App Store Connect takes at most this many screenshots per device.
    public static let maximumSlides = 10
    
    /// The main lineup's ID.
    public static let mainID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    
    public var id: UUID
    public var name: String
    public var devices: [DeviceClass]
    
    /// The slots to export.
    public var targets: [DeviceTarget.ID]
    
    /// The order is per set: 1 to 10 slides.
    public var slideIDs: [Slide.ID]
    
    /// An App Store Connect custom product page's ID, when the set uploads to that page instead of the product page.
    public var customProductPageID: String?
    
    public init(id: UUID = UUID(), name: String, devices: [DeviceClass], targets: [DeviceTarget.ID], slideIDs: [Slide.ID] = [], customProductPageID: String? = nil) {
        self.id = id
        self.name = name
        self.devices = devices
        self.targets = targets
        self.slideIDs = slideIDs
        self.customProductPageID = customProductPageID
    }
    
    // MARK: - Functions
    
    /// One target per class to start with: the largest iPhone size, or each class's first.
    public static func defaultTargets(for devices: [DeviceClass], table: DeviceTable = .standard) -> [DeviceTarget.ID] {
        devices.compactMap { device in
            let targets = table.targets(in: device)
            return (targets.first { $0.id == "iphone-dynamic-island-large" } ?? targets.first)?.id
        }
    }
    
    /// The set's targets from the device table, grouped in the order of its device classes.
    public func resolvedTargets(table: DeviceTable = .standard) -> [DeviceTarget] {
        let all = targets.compactMap(table.target(id:))
        return devices.flatMap { device in all.filter { $0.deviceClass == device } }
    }
}

/// One screenshot idea, like "Read the Land". It isn't tied to a device: it renders on every device it's on, each
/// with the template it picks there.
public struct Slide: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    
    /// The editor's name for it. Never rendered.
    public var title: String
    public var primary: Varying<Localized>
    public var secondary: Varying<Localized>
    
    /// The Main Device's capture key.
    public var captureKey: Varying<String>
    
    /// The template on each class (format 2's `variant`).
    public var template: Varying<TemplateID>
    
    /// The project's devices this slide isn't on.
    public var excludedDevices: Set<DeviceClass>
    
    /// Elements placed by the slide itself on a class, instead of by its template.
    public var detachments: [DeviceClass: Detachment]
    
    /// Content for the templates' extra elements, by element ID.
    public var extraContent: [ElementID: ElementContent]
    
    public init(
        id: UUID = UUID(),
        title: String,
        primary: Varying<Localized>,
        secondary: Varying<Localized>,
        captureKey: Varying<String>,
        template: Varying<TemplateID> = Varying(.straight),
        excludedDevices: Set<DeviceClass> = [],
        detachments: [DeviceClass: Detachment] = [:],
        extraContent: [ElementID: ElementContent] = [:]
    ) {
        self.id = id
        self.title = title
        self.primary = primary
        self.secondary = secondary
        self.captureKey = captureKey
        self.template = template
        self.excludedDevices = excludedDevices
        self.detachments = detachments
        self.extraContent = extraContent
    }
    
    // MARK: - Coding
    
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case primary
        case secondary
        case captureKey
        case template
        case excludedDevices
        case detachments
        case extraContent
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.primary = try container.decode(Varying<Localized>.self, forKey: .primary)
        self.secondary = try container.decode(Varying<Localized>.self, forKey: .secondary)
        self.captureKey = try container.decode(Varying<String>.self, forKey: .captureKey)
        self.template = try container.decode(Varying<TemplateID>.self, forKey: .template)
        self.excludedDevices = Set(try container.decodeIfPresent([DeviceClass].self, forKey: .excludedDevices) ?? [])
        self.detachments = try container.decodeIfPresent([DeviceClass: Detachment].self, forKey: .detachments) ?? [:]
        self.extraContent = try container.decodeIfPresent([ElementID: ElementContent].self, forKey: .extraContent) ?? [:]
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(primary, forKey: .primary)
        try container.encode(secondary, forKey: .secondary)
        try container.encode(captureKey, forKey: .captureKey)
        try container.encode(template, forKey: .template)
        
        // NOTE: - Sorted, since a set's order changes from run to run and would rewrite the file on every save.
        if !excludedDevices.isEmpty {
            try container.encode(DeviceClass.allCases.filter(excludedDevices.contains), forKey: .excludedDevices)
        }
        
        if !detachments.isEmpty {
            try container.encode(detachments, forKey: .detachments)
        }
        
        if !extraContent.isEmpty {
            try container.encode(extraContent, forKey: .extraContent)
        }
    }
    
    // MARK: - Functions
    
    public func text(_ role: TextRole) -> Varying<Localized> {
        switch role {
        case .primary: primary
        case .secondary: secondary
        }
    }
    
    public mutating func updateText(_ role: TextRole, _ body: (inout Varying<Localized>) -> Void) {
        switch role {
        case .primary: body(&primary)
        case .secondary: body(&secondary)
        }
    }
    
    public func isOn(_ device: DeviceClass) -> Bool {
        !excludedDevices.contains(device)
    }
    
    public mutating func setOn(_ device: DeviceClass, _ isOn: Bool) {
        if isOn {
            excludedDevices.remove(device)
        } else {
            excludedDevices.insert(device)
        }
    }
    
    /// Picks a template on a class (or every class that shares the base), clearing detachments made against the
    /// template it replaces.
    public mutating func setTemplate(_ id: TemplateID, for device: DeviceClass, scope: EditScope = .automatic) {
        let before = DeviceClass.allCases.map { template[$0] }
        template.set(id, for: device, scope: scope)
        
        for (index, device) in DeviceClass.allCases.enumerated() where template[device] != before[index] {
            detachments[device] = nil
        }
    }
    
    /// Whether an element is placed by this slide on a class instead of by its template.
    public func isDetached(_ element: ElementRef, on device: DeviceClass) -> Bool {
        detachments[device]?.placement(for: element) != nil
    }
    
    /// Gives an element back to the template on a class.
    public mutating func reattach(_ element: ElementRef, on device: DeviceClass) {
        detachments[device]?.setPlacement(nil, for: element)
        
        if detachments[device]?.isEmpty == true {
            detachments[device] = nil
        }
    }
    
    /// A file-name-safe version of the title, like `read-the-land`.
    public var slug: String {
        title.slugified
    }
}

/// The link to the app's Xcode project that the runner drives.
public struct AppLink: Codable, Hashable, Sendable {
    /// A bookmark to the `.xcodeproj` or `.xcworkspace`.
    public var project: Data
    
    /// The path when the link was made, shown when the bookmark can't be resolved.
    public var projectPath: String
    public var scheme: String
    
    /// For `-only-testing`.
    public var testTarget: String
    public var simulators: [DeviceClass: SimulatorSpec]
    
    /// Off when the app hides the status bar itself.
    public var overridesStatusBar: Bool
    
    /// Another scheme for a platform (`watchOS Simulator`, `macOS`), when its screenshot tests have their own.
    public var platformSchemes: [String: String]?
    
    /// Another test target for a platform, for `-only-testing:`.
    public var platformTestTargets: [String: String]?
    
    public init(
        project: Data,
        projectPath: String,
        scheme: String,
        testTarget: String,
        simulators: [DeviceClass: SimulatorSpec] = [:],
        overridesStatusBar: Bool = true,
        platformSchemes: [String: String]? = nil,
        platformTestTargets: [String: String]? = nil
    ) {
        self.project = project
        self.projectPath = projectPath
        self.scheme = scheme
        self.testTarget = testTarget
        self.simulators = simulators
        self.overridesStatusBar = overridesStatusBar
        self.platformSchemes = platformSchemes
        self.platformTestTargets = platformTestTargets
    }
    
    // MARK: - Computed Properties
    
    /// Whether the link is to a workspace rather than a project.
    public var isWorkspace: Bool {
        projectPath.hasSuffix(".xcworkspace")
    }
}

/// The simulator a device class is captured on.
public struct SimulatorSpec: Codable, Hashable, Sendable {
    /// From `xcrun simctl list -j devicetypes`.
    public var deviceType: String
    
    /// From `xcrun simctl list -j runtimes`.
    public var runtime: String
    
    /// Another Xcode's developer directory, like Xcode-Beta's for the iPhone Duo's iOS 27.1 simulator.
    public var developerDir: String?
    
    public init(deviceType: String, runtime: String, developerDir: String? = nil) {
        self.deviceType = deviceType
        self.runtime = runtime
        self.developerDir = developerDir
    }
}
