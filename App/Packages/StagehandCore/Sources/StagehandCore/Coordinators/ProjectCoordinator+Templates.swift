import CoreGraphics
import Foundation
import ImageIO
import StagehandModel

// MARK: - Functions

/// Templates, slides made from them, detachments, devices and bezel pinning.
extension ProjectCoordinator {
    /// What the canvas shows: the template being edited, or the selected cell.
    public var canvasScene: ResolvedScene? {
        if let templateID = selection.templateID {
            return templateScene(templateID, targetID: selection.targetID)
        }
        
        return selection.cell.flatMap { scene(for: $0) }
    }
    
    /// Whether the canvas edits a template (`true`) or a slide.
    public var isEditingTemplate: Bool {
        selection.templateID != nil
    }
    
    /// A template drawn on a target with its own placeholder text and no capture, never a slide's: a slide's text
    /// and screenshot are its own, and editing them doesn't touch the template.
    ///
    /// Its text is the size the slides on that device are drawn at, so a template and its slides always match: with
    /// one size for every slide, the lineup's fitted size; with each slide shrinking only to fit, the template set's
    /// size. A placeholder too long for that size overflows (``placeholderOverflow(_:targetID:)`` says so) rather than
    /// shrinking on its own, which made the template's text a different size from every slide's.
    public func templateScene(_ id: TemplateID, targetID: DeviceTarget.ID?, canvas: CGSize? = nil) -> ResolvedScene? {
        guard let template = project.style.template(id) else {
            return nil
        }
        
        let target = templateTarget(targetID)
        let slide = placeholderSlide(for: template)
        
        return Resolver.resolve(ResolveRequest(
            slide: slide,
            style: project.style,
            target: target,
            locale: selection.locale,
            sourceLocale: project.sourceLocale,
            captures: captureCatalog,
            bezels: bezels,
            fitted: slideTextSizes(on: target.deviceClass),
            lineHeights: lineHeights,
            canvas: canvas,
            assets: assetSizes
        ))
    }
    
    /// The text roles whose placeholder doesn't fit its box at the size the template is drawn at.
    public func placeholderOverflow(_ id: TemplateID, targetID: DeviceTarget.ID?) -> [TextRole] {
        guard let template = project.style.template(id) else {
            return []
        }
        
        let target = templateTarget(targetID)
        let own = autoFit.result(
            slides: [placeholderSlide(for: template)],
            style: project.style,
            target: target,
            locale: selection.locale,
            sourceLocale: project.sourceLocale
        )
        let drawn = slideTextSizes(on: target.deviceClass)?.sizes ?? [:]
        
        return TextRole.allCases.filter { role in
            guard let fits = own.slideSizes[Self.placeholderSlideID]?[role] else {
                return false
            }
            
            let size = drawn[role] ?? project.style.textStyle(role).size[target.deviceClass]
            return fits < size - 0.000_1
        }
    }
    
    private func templateTarget(_ targetID: DeviceTarget.ID?) -> DeviceTarget {
        targetID.flatMap(DeviceTable.standard.target(id:))
            ?? project.mainLineup.resolvedTargets().first
            ?? DeviceTable.standard.targets(in: .phone).first!
    }
    
    /// The text sizes the slides on a device are drawn at, when they share one (`nil` when each slide fits on its
    /// own, which leaves the template set's size).
    private func slideTextSizes(on device: DeviceClass) -> FittedText? {
        guard project.style.autoFitScope == .lineup else {
            return nil
        }
        
        let set = currentSet ?? project.mainLineup
        return FittedText(sizes: fitted(set: set, deviceClass: device, locale: selection.locale).sizes)
    }
    
    /// The stand-in slide a template is drawn with: its placeholder text in every locale, and no capture.
    func placeholderSlide(for template: Template) -> Slide {
        let locales = Set([project.sourceLocale, selection.locale])
        let text = { (role: TextRole) in
            Varying(Dictionary(uniqueKeysWithValues: locales.map { ($0, template.placeholder.text(role)) }))
        }
        
        return Slide(
            id: Self.placeholderSlideID,
            title: template.name,
            primary: text(.primary),
            secondary: text(.secondary),
            captureKey: Varying(""),
            template: Varying(template.id)
        )
    }
    
    /// One ID for every placeholder slide, so the fit cache keys on the text rather than a new ID each time.
    static let placeholderSlideID = UUID(uuidString: "00000000-0000-0000-0000-00000000F1A7")!
    
    /// The slides that use a template on any of their devices.
    public func slides(using template: TemplateID) -> [Slide] {
        project.slides(in: project.mainLineup).filter { slide in
            project.devices.contains { slide.isOn($0) && slide.template[$0] == template }
        }
    }
    
    /// Each asset's pixel size, read from its header, for image elements.
    var assetSizes: [String: CGSize] {
        var sizes: [String: CGSize] = [:]
        
        for (name, data) in document.contents.assets {
            if let cached = assetSizeCache[name], cached.byteCount == data.count {
                sizes[name] = cached.size
                continue
            }
            
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                continue
            }
            
            let size = CGSize(width: width, height: height)
            assetSizeCache[name] = (data.count, size)
            sizes[name] = size
        }
        
        return sizes
    }
    
    /// The project's devices that a template draws with a bezel, but that have no bezel in the library or the document.
    public var devicesMissingBezels: [DeviceClass] {
        let catalog = bezels
        
        return project.devices.filter { device in
            let wantsBezel = project.style.templates.contains { template in
                template.layouts[device].map { $0.device.bezel != .none && !$0.isHidden(.device) } ?? false
            }
            
            return wantsBezel && !catalog.bezels.values.contains { $0.deviceClass == device }
        }
    }
    
    /// Pinned bezels with a newer one in the library.
    var bezelIssues: [Issue] {
        let catalog = bezels
        
        return project.style.pinnedBezels.sorted().compactMap { id -> Issue? in
            guard let newer = catalog.newerBezel(than: id), let pinned = catalog.bezels[id] else {
                return nil
            }
            
            return Issue(
                kind: .newerBezel(id, newer: newer.id),
                severity: .info,
                message: "A newer bezel is available for \(pinned.deviceClass.displayName): \(newer.displayName). Update it from the template's Device section.",
                setID: ShotSet.mainID
            )
        }
    }
    
    // MARK: - Slides
    
    func addSlide(template: TemplateID?, at index: Int?) {
        let setID = selection.setID ?? ShotSet.mainID
        let templateID = template ?? project.style.templates.first?.id ?? .straight
        let count = project.slides.count + 1
        var title = project.style.template(templateID).map { "\($0.name) \(count)" } ?? "Slide \(count)"
        
        while project.slides.values.contains(where: { $0.title == title }) {
            title += " Copy"
        }
        
        let placeholder = project.style.template(templateID)?.placeholder ?? .standard
        let slide = Project.newSlide(title: title, template: templateID, locale: project.sourceLocale, placeholder: placeholder)
        
        edit("Add Slide") { contents in
            contents.project.slides[slide.id] = slide
            contents.project.updateSet(id: setID) { set in
                let position = index.map { min(max($0, 0), set.slideIDs.count) } ?? set.slideIDs.count
                set.slideIDs.insert(slide.id, at: position)
            }
        }
        
        selection.slideID = slide.id
        selection.templateID = nil
    }
    
    func setExtraText(_ element: ElementID, _ text: String) {
        editCurrentSlide("Edit Text") { slide, device, locale in
            var value = slide.extraContent[element]?.text ?? Varying(Localized())
            value.setText(text, for: device, locale: locale)
            slide.extraContent[element] = .text(value)
        }
    }
    
    func setExtraCapture(_ element: ElementID, _ key: String) {
        editCurrentSlide("Change Capture") { slide, device, _ in
            var value = slide.extraContent[element]?.captureKey ?? Varying("")
            value.set(key, for: device)
            slide.extraContent[element] = .capture(value)
        }
    }
    
    /// Copies an image into the project's assets and shows it in an image element on the current slide.
    func setExtraImage(_ element: ElementID, _ file: DroppedFile) {
        guard CGImage.decode(file.data) != nil else {
            alert = CoordinatorAlert(title: "Couldn't Use This Image", message: "\(file.name) isn't an image Stagehand can read.")
            return
        }
        
        let name = file.name
        
        edit("Change Image") { contents in
            contents.assets[name] = file.data
            
            if let id = selection.slideID {
                contents.project.slides[id]?.extraContent[element] = .image(name)
            }
        }
    }
    
    // MARK: - Detaching
    
    /// Copies an element's current placement (the template's) into the slide's detachment, so it can move on its own.
    func detach(_ element: ElementRef) {
        pendingDetach = nil
        
        guard let slide = currentSlide else {
            return
        }
        
        let device = currentDeviceClass
        let layout = Resolver.layout(for: slide, style: project.style, device: device).layout
        
        guard let placement = layout.placement(for: element) else {
            return
        }
        
        editCurrentSlide("Detach from Template") { slide, device, _ in
            slide.detachments[device, default: Detachment()].setPlacement(placement, for: element)
        }
    }
    
    func reattach(_ element: ElementRef?) {
        editCurrentSlide("Reset to Template") { slide, device, _ in
            if let element {
                slide.reattach(element, on: device)
            } else {
                slide.detachments[device] = nil
            }
        }
    }
    
    // MARK: - Templates
    
    func selectTemplate(_ id: TemplateID?) {
        selection.templateID = id
        
        if id != nil {
            mode = .canvas
            
            // Show the template on a class it has a layout for.
            if let template = id.flatMap(project.style.template), template.layouts[currentDeviceClass] == nil,
               let device = project.devices.first(where: { template.layouts[$0] != nil }) {
                selection.targetID = project.targets.first { DeviceTable.standard.target(id: $0)?.deviceClass == device }
            }
        }
    }
    
    func addTemplate(duplicating source: TemplateID?) {
        var template: Template
        
        if let source, let original = project.style.template(source) {
            template = original
            template.id = .make()
            template.name = original.name + " Copy"
        } else {
            template = Template(name: uniqueTemplateName("Untitled Template"))
            
            for device in project.devices {
                var layout = Template.blankLayout(for: device)
                layout.device.bezel = defaultBezelChoice(for: device, current: layout.device.bezel)
                template.layouts[device] = layout
            }
        }
        
        let added = template
        
        edit("Add Template") { contents in
            contents.project.style.templates.append(added)
            embedPinnedBezels(in: &contents)
        }
        
        selectTemplate(added.id)
    }
    
    /// Deletes a template, unless it's the last. Slides that used it move to the first remaining template.
    func deleteTemplate(_ id: TemplateID) {
        guard project.style.templates.count > 1 else {
            alert = CoordinatorAlert(title: "Can't Delete the Last Template", message: "A project needs at least one template. Add another before deleting this one.")
            return
        }
        
        edit("Delete Template") { contents in
            contents.project.style.templates.removeAll { $0.id == id }
            
            guard let fallback = contents.project.style.templates.first?.id else {
                return
            }
            
            for slideID in contents.project.slides.keys {
                guard var slide = contents.project.slides[slideID] else {
                    continue
                }
                
                for device in DeviceClass.allCases where slide.template[device] == id {
                    slide.setTemplate(fallback, for: device, scope: slide.template.isOverridden(for: device) ? .override : .shared)
                }
                
                contents.project.slides[slideID] = slide
            }
            
            embedPinnedBezels(in: &contents)
        }
        
        if selection.templateID == id {
            selection.templateID = nil
        }
    }
    
    func addTemplateLayout(_ device: DeviceClass, from source: DeviceClass?) {
        guard let id = selection.templateID else {
            return
        }
        
        let pinned = defaultBezelChoice(for: device, current: nil)
        
        edit("Add \(device.displayName) Layout") { contents in
            contents.project.style.updateTemplate(id) { template in
                if let source, let layout = template.layouts[source] {
                    template.layouts[device] = layout
                    
                    // A bezel is made for one class, so a copied layout gets this class's.
                    template.layouts[device]?.device.bezel = layout.device.bezel == .none ? .none : pinned
                } else {
                    var layout = Template.blankLayout(for: device)
                    
                    if layout.device.bezel != .none {
                        layout.device.bezel = pinned
                    }
                    
                    template.layouts[device] = layout
                }
            }
            
            embedPinnedBezels(in: &contents)
        }
        
        if let target = project.targets.first(where: { DeviceTable.standard.target(id: $0)?.deviceClass == device }) {
            selection.targetID = target
        }
    }
    
    /// Adds an extra element to the current template, placed on the current class.
    func addElement(_ kind: TemplateElement.Kind) {
        guard let id = selection.templateID else {
            return
        }
        
        let count = (currentTemplate?.elements.filter { $0.kind == kind }.count ?? 0) + 1
        var element = TemplateElement(name: "\(kind.displayName) \(count)", kind: kind)
        element.textStyle = .secondary
        var placement = element.defaultPlacement()
        let device = currentDeviceClass
        
        if case var .device(devicePlacement) = placement {
            devicePlacement.bezel = defaultBezelChoice(for: device, current: nil)
            placement = .device(devicePlacement)
        }
        
        let added = element
        let placed = placement
        
        edit("Add \(kind.displayName)") { contents in
            contents.project.style.updateTemplate(id) { template in
                template.elements.append(added)
                template.layouts[device]?.extras[added.id] = placed
            }
            
            embedPinnedBezels(in: &contents)
        }
    }
    
    func removeElement(_ element: ElementID) {
        guard let id = selection.templateID else {
            return
        }
        
        edit("Remove Element") { contents in
            contents.project.style.updateTemplate(id) { template in
                template.elements.removeAll { $0.id == element }
                
                for device in template.layouts.keys {
                    template.layouts[device]?.extras[element] = nil
                }
            }
            
            for slideID in contents.project.slides.keys {
                contents.project.slides[slideID]?.extraContent[element] = nil
            }
            
            embedPinnedBezels(in: &contents)
        }
    }
    
    /// Hides or shows a standard element, or places or removes an extra one, on the current class.
    func setElementShown(_ element: ElementRef, _ isShown: Bool) {
        guard let id = selection.templateID else {
            return
        }
        
        let device = currentDeviceClass
        
        edit(isShown ? "Show Element" : "Hide Element") { contents in
            contents.project.style.updateTemplate(id) { template in
                switch element {
                case let .extra(elementID):
                    let placement = isShown ? template.element(elementID)?.defaultPlacement() : nil
                    template.layouts[device]?.extras[elementID] = placement
                default:
                    if let standard = element.standard {
                        template.layouts[device]?.setHidden(standard, !isShown)
                    }
                }
            }
        }
    }
    
    /// Sets a device element's bezel on the current template's layout for the current class, embedding it.
    func setBezel(_ element: ElementRef, _ choice: BezelChoice) {
        guard let id = selection.templateID else {
            return
        }
        
        let device = currentDeviceClass
        
        edit("Change Bezel") { contents in
            contents.project.style.updateTemplate(id) { template in
                guard case var .device(placement)? = template.layouts[device]?.placement(for: element) else {
                    return
                }
                
                placement.bezel = choice
                template.layouts[device]?.setPlacement(.device(placement), for: element)
            }
            
            embedPinnedBezels(in: &contents)
        }
    }
    
    // MARK: - Devices
    
    /// Adds a device. Templates without a layout for it are flagged until one is added.
    func addDevice(_ device: DeviceClass, includeExistingSlides: Bool) {
        edit("Add \(device.displayName)") { $0.project.addDevice(device, includeExistingSlides: includeExistingSlides) }
        repairSelection()
    }
    
    // MARK: - Bezels
    
    /// The bezel a new layout pins on a class: the library's newest whose screen matches the class's first export
    /// size, or the library default. Without any bezel for the class, it keeps `current` (or Library Default).
    func defaultBezelChoice(for device: DeviceClass, current: BezelChoice?) -> BezelChoice {
        BezelPinning.bestChoice(for: device, targets: project.targets, catalog: libraryBezels) ?? current ?? .matchTarget
    }
    
    /// Copies every bezel the template set pins into the document (from the library), and drops copies no longer
    /// pinned.
    func embedPinnedBezels(in contents: inout ProjectContents) {
        let library = bezelLibrary
        BezelPinning.embed(in: &contents, catalog: libraryBezels.merging(embedded: contents.bezels)) { id in
            try? library?.imageData(for: id)
        }
    }
    
    // MARK: - Helpers
    
    func uniqueTemplateName(_ base: String) -> String {
        let names = Set(project.style.templates.map(\.name))
        var name = base
        var number = 2
        
        while names.contains(name) {
            name = "\(base) \(number)"
            number += 1
        }
        
        return name
    }
}
