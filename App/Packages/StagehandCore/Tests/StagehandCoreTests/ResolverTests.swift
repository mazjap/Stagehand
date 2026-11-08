import CoreGraphics
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct ResolverTests {
    private let project = Project.fixture()
    private let phone = DeviceTable.target("iphone-dynamic-island-large")
    private let pad = DeviceTable.target("ipad-13")
    
    private var slide: Slide {
        project.slides(in: project.mainLineup)[0]
    }
    
    private func catalog(_ addresses: [CaptureAddress], width: Int = 1320, height: Int = 2868) -> CaptureCatalog {
        CaptureCatalog(entries: Dictionary(uniqueKeysWithValues: addresses.map {
            ($0, CaptureCatalog.Entry(ref: .capture($0, revision: 1), pixelWidth: width, pixelHeight: height))
        }))
    }
    
    private func resolve(
        _ slide: Slide? = nil,
        style: Style? = nil,
        target: DeviceTarget? = nil,
        locale: LocaleID = "en-US",
        captures: CaptureCatalog = CaptureCatalog(),
        bezels: BezelCatalog = .empty,
        fitted: FittedText? = nil
    ) -> ResolvedScene {
        Resolver.resolve(ResolveRequest(
            slide: slide ?? self.slide,
            style: style ?? project.style,
            target: target ?? phone,
            locale: locale,
            sourceLocale: "en-US",
            captures: captures,
            bezels: bezels,
            fitted: fitted
        ))
    }
    
    @Test func textIsResolvedWithItsLetterCase() throws {
        let scene = resolve()
        let primary = try #require(scene.primary)
        #expect(primary.string == "READ THE LAND")
        #expect(primary.font.size == 0.085 * 1320)
        #expect(primary.color == RGBA(hex: "#FFA43C"))
        #expect(scene.secondary?.string == "Topo maps with every trail, peak and spring")
    }
    
    @Test func textFallsBackToSourceLocale() {
        let scene = resolve(locale: "de")
        #expect(scene.primary?.string == "READ THE LAND")
        #expect(scene.flags.contains(.textFallback(.primary, locale: "de")))
    }
    
    /// Format 2 let the Duo borrow the iPad's layout. Templates don't borrow: a class no template has a layout for is
    /// flagged.
    @Test func theDuoDoesNotBorrowTheIPadLayout() {
        let scene = resolve(target: DeviceTable.target("iphone-duo-outer"))
        #expect(scene.flags.contains(.missingLayout(.duoOuter)))
    }
    
    @Test func aClassWithNoLayoutIsFlagged() {
        var style = project.style
        
        for index in style.templates.indices {
            style.templates[index].layouts[.mac] = nil
        }
        
        let scene = resolve(style: style, target: DeviceTable.target("mac"))
        #expect(scene.flags.contains(.missingLayout(.mac)))
    }
    
    @Test func aTemplateWithoutALayoutForTheClassFallsBackToTheFirstThatHasOne() {
        var zoomed = slide
        zoomed.template = Varying(.zoomed)
        let scene = resolve(zoomed, target: pad)
        let straight = resolve(target: pad)
        #expect(scene.flags.contains(.templateFallback(.zoomed)))
        #expect(scene.device!.rotation == straight.device!.rotation)
        #expect(scene.device!.center == straight.device!.center)
    }
    
    @Test func aDetachedDeviceUsesTheSlidesOwnPlacement() throws {
        var detached = slide
        let own = DevicePlacement(position: NormPoint(x: 0.3, y: 0.5), width: 0.5, rotation: -4)
        detached.detachments[.phone] = Detachment(device: own)
        let scene = resolve(detached)
        let template = resolve()
        
        #expect(scene.device!.rotation == -4)
        #expect(abs(scene.device!.center.x - 0.3 * 1320) < 0.001)
        #expect(scene.primary?.frame == template.primary?.frame)
        #expect(resolve(detached, target: pad).device == resolve(target: pad).device)
    }
    
    @Test func hiddenStandardElementsAreNotDrawn() {
        var style = project.style
        style.updateTemplate(.straight) { $0.layouts[.phone]?.setHidden(.secondary, true) }
        style.updateTemplate(.straight) { $0.layouts[.phone]?.setHidden(.device, true) }
        let scene = resolve(style: style)
        
        #expect(scene.secondary == nil)
        #expect(scene.device == nil)
        #expect(scene.primary != nil)
        #expect(!scene.flags.contains { if case .missingCapture = $0 { true } else { false } })
    }
    
    @Test func extraElementsDrawTheSlidesContent() throws {
        var style = project.style
        let badge = TemplateElement(id: "badge", name: "Badge", kind: .text, textStyle: .secondary)
        let second = TemplateElement(id: "second", name: "Second Phone", kind: .device)
        let logo = TemplateElement(id: "logo", name: "Logo", kind: .image)
        style.updateTemplate(.straight) { template in
            template.elements = [badge, second, logo]
            template.layouts[.phone]?.extras = [
                "badge": badge.defaultPlacement(),
                "second": second.defaultPlacement(),
                "logo": .image(ImagePlacement(position: NormPoint(x: 0.5, y: 0.9), width: 0.2)),
            ]
        }
        
        var slide = slide
        slide.extraContent = [
            "badge": .text(Varying(["en-US": "New"])),
            "second": .capture(Varying("second-screen")),
            "logo": .image("logo.png"),
        ]
        
        let scene = Resolver.resolve(ResolveRequest(
            slide: slide,
            style: style,
            target: phone,
            locale: "en-US",
            sourceLocale: "en-US",
            captures: CaptureCatalog(),
            assets: ["logo.png": CGSize(width: 200, height: 100)]
        ))
        
        #expect(scene.extras.map(\.id) == ["badge", "second", "logo"])
        #expect(scene.extrasInFront.map(\.id) == ["badge"])
        #expect(scene.flags.contains(.missingCapture(CaptureAddress(key: "second-screen", deviceClass: .phone, locale: "en-US"))))
        
        guard case let .image(image) = scene.extra("logo")?.content else {
            Testing.Issue.record("The logo isn't an image")
            return
        }
        
        #expect(image.image == .asset("logo.png"))
        #expect(abs(image.size.width - 0.2 * 1320) < 0.001)
        #expect(abs(image.size.height - 0.1 * 1320) < 0.001)
        #expect(resolve(slide, style: style, target: pad).extras.isEmpty)
    }
    
    @Test func aSlideCanBeTiltedOnIPhoneAndStraightOnIPad() {
        let bring = project.slides(in: project.mainLineup)[1]
        #expect(resolve(bring, target: phone).device?.rotation == 9)
        #expect(resolve(bring, target: pad).device?.rotation == 0)
    }
    
    @Test func aMissingCaptureIsFlagged() {
        let scene = resolve()
        #expect(scene.device!.capture == nil)
        #expect(scene.flags.contains(.missingCapture(CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "en-US"))))
    }
    
    @Test func aCaptureFallsBackToTheSourceLocaleAndIsFlagged() {
        let source = CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "en-US")
        let scene = resolve(locale: "de", captures: catalog([source]))
        #expect(scene.device!.capture == .capture(source, revision: 1))
        #expect(scene.flags.contains(.captureFallbackLocale(CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "de"))))
    }
    
    @Test func theCaptureKeyCanVaryByClass() {
        var slide = slide
        slide.captureKey = Varying("read-the-land", overrides: [.watch: "watch-map"])
        let watch = CaptureAddress(key: "watch-map", deviceClass: .watch, locale: "en-US")
        let scene = resolve(slide, target: DeviceTable.target("watch"), captures: catalog([watch], width: 422, height: 514))
        #expect(scene.device!.capture == .capture(watch, revision: 1))
    }
    
    @Test func framesScaleInProportionAcrossTargetsInAClass() throws {
        let large = resolve(target: phone)
        let medium = resolve(target: DeviceTable.target("iphone-dynamic-island-medium"))
        let ratio = 1206.0 / 1320.0
        
        let largePrimary = try #require(large.primary)
        let mediumPrimary = try #require(medium.primary)
        
        #expect(abs(mediumPrimary.frame.width - largePrimary.frame.width * ratio) < 0.01)
        #expect(abs(mediumPrimary.font.size - largePrimary.font.size * ratio) < 0.01)
        #expect(abs(medium.device!.size.width - large.device!.size.width * ratio) < 0.01)
        #expect(abs(medium.device!.center.x / medium.canvas.width - large.device!.center.x / large.canvas.width) < 0.0001)
        #expect(abs(mediumPrimary.frame.height - largePrimary.frame.height * ratio) < 0.01)
    }
    
    @Test func aBezelPlacesTheScreenAtItsRect() {
        let bezel = BezelInfo(
            id: "phone-test",
            name: "Test",
            deviceClass: .phone,
            model: "Test",
            color: "Black",
            imageWidth: 600,
            imageHeight: 1200,
            screenRect: TestImages.bezelScreen
        )
        let scene = resolve(bezels: BezelCatalog(bezels: [bezel.id: bezel], defaults: [.phone: bezel.id]))
        let scale = 0.8 * 1320 / 600
        
        #expect(scene.device!.frame == .bezel)
        #expect(scene.device!.bezel == bezel.imageRef)
        #expect(abs(scene.device!.screen.minX - 60 * scale) < 0.001)
        #expect(abs(scene.device!.size.height - 1200 * scale) < 0.001)
        #expect(!scene.flags.contains(.missingBezel(.phone)))
    }
    
    @Test func aMissingBezelDrawsAPlainFrameAndIsFlagged() {
        let scene = resolve()
        #expect(scene.device!.frame == .placeholder)
        #expect(scene.flags.contains(.missingBezel(.phone)))
    }
    
    @Test func noBezelDrawsTheCaptureAlone() {
        let watch = CaptureAddress(key: "read-the-land", deviceClass: .watch, locale: "en-US")
        let scene = resolve(target: DeviceTable.target("watch"), captures: catalog([watch], width: 422, height: 514))
        #expect(scene.device!.frame == .bare)
        #expect(!scene.flags.contains(.missingBezel(.watch)))
        #expect(abs(scene.device!.size.width / scene.device!.size.height - 422.0 / 514.0) < 0.0001)
    }
    
    @Test func fittedSizesAndOverflowComeFromAutoFit() {
        let scene = resolve(fitted: FittedText(sizes: [.primary: 0.05], overflowing: [.primary]))
        #expect(scene.primary?.font.size == 0.05 * 1320)
        #expect(scene.flags.contains(.overflow(.primary)))
    }
    
    @Test func aWrongSizedCaptureIsFlagged() {
        let address = CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "en-US")
        let scene = resolve(captures: catalog([address], width: 2064, height: 2752))
        #expect(scene.flags.contains(.captureSizeMismatch(address)))
    }
    
    /// Regression test: the iPhone Duo's iOS 27.2 simulator takes inner display screenshots a pixel short of its target.
    @Test func aCaptureWithinTheSizeToleranceIsNotFlagged() {
        let address = CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "en-US")
        let scene = resolve(captures: catalog([address], width: 1319, height: 2867))
        #expect(!scene.flags.contains(.captureSizeMismatch(address)))
    }
    
    @Test func theGlowIsABlurOfTheDevice() throws {
        let glow = try #require(resolve().device?.glow)
        #expect(glow.blur == 0.07 * 1320)
        #expect(glow.spread == 1.02)
        #expect(glow.color == RGBA(hex: "#FFA43C"))
        #expect(glow.offset == .zero)
    }
    
    @Test func aTextBoxIsAsTallAsItsLinesAtItsFontSize() throws {
        let scene = Resolver.resolve(ResolveRequest(
            slide: slide,
            style: project.style,
            target: phone,
            locale: "en-US",
            sourceLocale: "en-US",
            captures: CaptureCatalog(),
            lineHeights: [.systemHeavy: 1.25]
        ))
        let primary = try #require(scene.primary)
        let size = 0.085 * 1320
        
        #expect(abs(primary.frame.height - 2 * size * 1.25) < 0.001)
        #expect(abs(primary.frame.midX - 660) < 0.001)
        #expect(abs(primary.frame.minY - 0.055 * 2868) < 0.001)
    }
    
    @Test func aBottomAnchoredBoxGrowsUpward() throws {
        var style = project.style
        style.updateTemplate(.straight) { $0.layouts[.phone]?.primary.anchor = .bottom }
        let small = try #require(resolve(style: style, fitted: FittedText(sizes: [.primary: 0.05])).primary)
        let large = try #require(resolve(style: style).primary)
        
        #expect(abs(small.frame.maxY - large.frame.maxY) < 0.001)
        #expect(large.frame.minY < small.frame.minY)
    }
    
    @Test func aDeviceIsPlacedByItsAnchor() {
        var style = project.style
        let centered = resolve(style: style).device!
        style.updateTemplate(.straight) { $0.layouts[.phone]?.device.anchor = .top }
        let topAnchored = resolve(style: style).device!
        
        #expect(abs(topAnchored.center.y - (centered.center.y + centered.size.height / 2)) < 0.001)
        #expect(abs(Resolver.devicePoint(.top, center: topAnchored.center, size: topAnchored.size, rotation: 0).y - 0.63 * 2868) < 0.001)
    }
    
    @Test func aScaledDeviceKeepsItsAnchorInPlace() {
        var style = project.style
        style.updateTemplate(.straight) { $0.layouts[.phone]?.device.anchor = .bottomLeading }
        style.updateTemplate(.straight) { $0.layouts[.phone]?.device.width *= 0.5 }
        let device = resolve(style: style).device!
        let corner = Resolver.devicePoint(.bottomLeading, center: device.center, size: device.size, rotation: 0)
        
        #expect(abs(corner.x - 0.5 * 1320) < 0.001)
        #expect(abs(corner.y - 0.63 * 2868) < 0.001)
    }
}
