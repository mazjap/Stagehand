# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Stagehand is a personal SwiftUI app for macOS 27 and iPadOS 27 that makes App Store screenshots for the user's apps (TrekPoint, Flask Master, and others). The repository is public (`github.com/mazjap/Stagehand`) so others can build the app and use the kit, but the app isn't distributed as a build or on the App Store. A project's template set has templates (like Straight, Tilted and Zoomed) that lay out a primary and a secondary text label, a device bezel and a raw screenshot once per device class, slides are made from templates, and Stagehand renders every App Store Connect size from that. The raw screenshots come from each app's screenshot UI tests, which use Stagehand's capture kit: a Swift package in this repository that those test targets depend on, and that Stagehand's capture runner drives with `xcodebuild`.

Stagehand is just starting. **PLAN.md is the design and TASKS.md is the work list, in order.** As each part is built, describe it under Architecture below (what it does, where it lives, the decisions behind it, and its gotchas), trim it from PLAN.md, and check it off in TASKS.md. Check both files before proposing features, and update them when a listed item ships.

Paths in this file are relative to the repository root:

- `Package.swift`, `Sources/` and `Tests/` are the capture kit: `StagehandModel` (device classes, `devices.json`, capture metadata), `StagehandCapture` (for UI test targets) and `StagehandScene` (for app targets). Other apps add this repository by URL, so the kit stays at the root and has no dependencies.
- `App/` is the app: `App/Stagehand.xcodeproj`, the app target in `App/Stagehand/`, its tests in `App/StagehandTests/`, and most of its code in the local package `App/Packages/StagehandCore/` (documents, the resolver, the renderer, bezels, the capture runner, and the App Store Connect client). StagehandCore depends on the kit by path.
- `Fixtures/StagehandFixtureApp/` is a tiny iOS app with a screenshot UI test target that uses the kit, for the runner's end-to-end tests.
- `README.md` is the guide for people: building and using the app, and adding the kit to an app. `skills/stagehand/SKILL.md` is the same for coding agents (in this repository and in apps that use the kit), linked into `.claude/skills/stagehand`.

The bundle identifier is `com.mazjap.Stagehand`. Projects are `.stagehand` packages (`com.mazjap.stagehand.project`), and styles are `.stagehandstyle` packages (`com.mazjap.stagehand.style`).

## Platforms

- **The app's minimum is macOS 27 and iPadOS 27.** There's no iPhone version. It's native on both (not Mac Catalyst or Designed for iPad), and nothing older is supported, so the app needs no `#available` fallbacks. It's built and used on the Mac only for now; keep the iPad build compiling (see Commands) for when there's an iPad.
- **Capturing is Mac-only.** It launches `xcodebuild`, `simctl` and `xcresulttool` with `Process`. Keep runner code behind `#if os(macOS)`, and hide its UI on iPad.
- **The capture kit runs inside other apps' targets,** so its platforms follow the oldest of them (TrekPoint supports iOS 17): iOS 17, macOS 14 and watchOS 10. It needs `#available` and `#if os(...)` checks where APIs differ, and its minimums never rise just because Stagehand's are newer.
- **The macOS target has App Sandbox turned off,** since it runs Xcode's tools and reads app projects anywhere on disk. That's only acceptable because Stagehand is never distributed as a build; people build it themselves.
- **Everything builds in Swift 6 language mode** (complete concurrency checking): the app, StagehandCore and the kit.

## Agent skills

If Apple's Xcode skills are exported into `xcode-skills/` (as in TrekPoint: `DEVELOPER_DIR=/Applications/Xcode-Beta.app/Contents/Developer xcrun agent skills export --replace-existing`), link the ones that apply into `.claude/skills/` with `ln -s ../../xcode-skills/<name> .claude/skills/<name>`. Both the export and those links are ignored by git, since they're per machine; only `.claude/skills/stagehand` (a link to the tracked `skills/stagehand/`) is committed. These apply here: the SwiftUI specialist, what's new in 27, `building-document-based-swiftui-applications` (Stagehand is a document-based app), and `modernize-tests`. Re-export after installing a new Xcode.

## Setup

- **Xcode:** Xcode 27 builds Stagehand. Capturing on the iPhone Duo needs the iOS 27.1 simulator from Xcode 27.1 (Xcode-Beta, `/Applications/Xcode-Beta.app`). The runner picks a developer directory for each device class (`SimulatorSpec.developerDir`), and the kit must also build with Xcode-Beta, since the iOS 27.1 SDK checks concurrency more strictly.
- **App Store Connect API key:** the `.p8` key, its key ID and the issuer ID are stored in the Keychain from Stagehand's settings. Never commit a key, and never write one to a file in the repository.
- **Bezels:** Stagehand downloads Apple's product bezels from Apple Design Resources into the library's `Bezels/` folder (iCloud Drive › Stagehand) from the Library window, after the user agrees to each disk image's license. They're Apple's files: never commit or bundle them. Tests draw their own synthetic bezel.
- **iCloud:** the library lives in the app's iCloud container (`iCloud.com.mazjap.Stagehand`), so the app needs the iCloud Documents capability and a signing team.

## Commands

There's no linter or formatter configured.

```sh
# Capture kit tests (StagehandModel, and StagehandCapture's logic with fixture images)
swift test

# Core tests: the model, resolver, documents, renderer snapshots, runner (with a fake process runner),
# and App Store Connect client
swift test --package-path App/Packages/StagehandCore

# Build and test the app on the Mac
xcodebuild build -project App/Stagehand.xcodeproj -scheme Stagehand -destination 'platform=macOS'
xcodebuild test -project App/Stagehand.xcodeproj -scheme Stagehand -destination 'platform=macOS'

# Keep the iPad build compiling
xcodebuild build -project App/Stagehand.xcodeproj -scheme Stagehand -destination 'generic/platform=iOS'

# The kit has to compile for every platform the apps use
xcodebuild build -scheme Stagehand-Package -destination 'generic/platform=iOS'
xcodebuild build -scheme Stagehand-Package -destination 'generic/platform=watchOS'
DEVELOPER_DIR=/Applications/Xcode-Beta.app/Contents/Developer swift build

# One suite, or one test (Swift Testing functions include their parentheses)
swift test --package-path App/Packages/StagehandCore --filter ResolverTests
swift test --package-path App/Packages/StagehandCore --filter 'ResolverTests/textFallsBackToSourceLocale()'

# End to end: the runner drives Fixtures/StagehandFixtureApp's screenshot tests (slow, opt-in)
STAGEHAND_E2E=1 swift test --package-path App/Packages/StagehandCore --filter EndToEndTests

# The Mac end-to-end test drives the real desktop and needs UI automation permission, so it's opt-in on its own
STAGEHAND_E2E=1 STAGEHAND_E2E_MAC=1 swift test --package-path App/Packages/StagehandCore --filter 'EndToEndTests/theRunnerCapturesTheFixtureMacApp()'
```

Run one `xcodebuild test` (or end-to-end run) at a time: two simulators booting at once can crash CoreSimulator ("server died"). If a simulator refuses to launch the test runner ("Busy", "failed preflight checks"), shut it down, boot it again and rerun.

## Rules

- **Keep `README.md` and `skills/stagehand/SKILL.md` up to date in the same change** as anything that changes how the kit or the app is used: the kit's public API, its behavior or its environment variables, how captures are named, matched or imported, and the app's behavior, menus, shortcuts and workflows. The README covers what the app's users see and do; the skill covers what an agent needs to add the kit to an app, set up a capture run, or help someone use Stagehand. Check both before calling a change done, and keep their examples compiling against the kit.
- **Never upload anything to App Store Connect without asking the user and getting an explicit yes, every time,** even when they seem to imply it. The same goes for deleting or reordering screenshots there. A dry run that shows what an upload would change is fine.
- **Captures run on Stagehand's own simulators** ("Stagehand <target>"), which the runner creates. Never boot, erase or change the user's own simulators.
- **`devices.json` (in `StagehandModel`) is the only source of screenshot sizes.** The app and the kit both read it. Change sizes there, never in code, and check it against Apple's Screenshot specifications page when new devices are announced.
- **The kit's public API and its metadata format are used by other repositories at pinned versions.** A breaking API change needs a new major version (a new minor before 1.0). A change to `Shot` needs a new `schemaVersion`, and Stagehand keeps reading the old ones.
- **Work in another app's repository** (like moving its screenshot target onto the kit) follows that repository's CLAUDE.md. TrekPoint, for example, takes changes to its screenshot tests alone straight to its open release branch, and anything that touches the app target goes into a pull request there. Adding the kit changes the Xcode project and `Package.resolved`, so ask which of those that is before committing.

## Git workflow

- `main` is what the user runs. It always builds for the Mac and the iPad, and its tests pass.
- Each change or bug fix gets its own branch off an up-to-date `main` (`feature/…` or `fix/…`, named after the task), with its tests, and goes into a pull request to `main` (`gh pr create --base main`), which the user tests and merges. Don't commit to `main` or merge pull requests, except for changes to tests alone and to CLAUDE.md, PLAN.md and TASKS.md, which go straight to `main` once tests pass. A bug fix with its regression test still gets a pull request.
- Capture kit releases are annotated `v<major.minor.patch>` tags on `main` (like `v0.1.0`), made only when the user asks, and pushed explicitly (`git push origin <tag>`; a plain push doesn't send tags). Branches are never named like tags.
- The user may also edit in this checkout, so commit only your own files by explicit path, and leave uncommitted changes you didn't make alone. If they would block switching branches, ask instead of stashing or discarding them.

## Architecture

What's still to build is in PLAN.md and TASKS.md. These decisions shape all of the code:

- **The model is Codable value types,** saved as JSON in document packages (`project.json`, `style.json`), not SwiftData. Never rename a Codable key or an enum case's raw value in place: bump `formatVersion` and migrate on open.
- **`Varying<T>` is how linking works.** A value is shared across device classes (`base`) unless a class overrides it. Slide text, capture keys, each slide's template, and the style's fonts, sizes and colors are all `Varying`. Linked-by-default behavior and the inspector's link badges are built on this one type, not reimplemented per property. Remove an override when it becomes equal to the base.
- **Templates lay slides out, and slides follow them.** A template (in the template set, `Style.templates`) has its own layout for each device class: where Primary Text, Secondary Text and the Main Device sit, the bezel, and any extra elements. Moving something in the template editor moves it on every slide using that template. On a slide, elements are locked to the template until the user confirms detaching one, which copies it into the slide's `Detachment` for that class.
- **The project owns its devices, and slides live in a pool in one order.** Devices are added one at a time (`Project.devices`), each slide can be off for any of them (`Slide.excludedDevices`), and every device shows the project's order, skipping the slides that are off for it. Custom product pages (`ProductPage`) reference slides from the same pool. Lineups (`ShotSet`, the name sets had in format 2) are computed from these, never saved.
- **`resolve` is a pure function** (slide, style, target, locale, captures, bezels, asset sizes and text line counts in; a `ResolvedScene` out), and the core of the app. Keep anything that measures, loads or renders out of it.
- **One SwiftUI view renders both the canvas and the export** (through `ImageRenderer` at scale 1). It's pure SwiftUI, since `ImageRenderer` skips views backed by AppKit or UIKit.
- **Layouts use normalized coordinates,** and sizes are fractions of the canvas width, so one template layout covers every target in a device class. The inspector shows text sizes in points on the target the canvas shows (`ProjectCoordinator.points(fromFraction:)`; a point is a pixel of the export, as design apps count a 72-dpi image), but stores the fraction.
- **Captures are classified by pixel size** through the device table, never by idiom or device name.
- **State lives in `@Observable @MainActor` coordinators** (a project coordinator for the document, one for the canvas, one for capture runs). Views send user actions as intent enums to the coordinator's `handle(_:)` and receive small read-only state structs. Business logic doesn't live in views.
- **Dependencies use [swift-dependencies](https://github.com/pointfreeco/swift-dependencies)** in StagehandCore and the app (never in the kit, which has no dependencies). Each manager or service is registered in the same file that defines it, with a computed `testValue` so each test gets a fresh instance:

  ```swift
  enum CaptureRunnerKey: DependencyKey {
      static let liveValue = CaptureRunner()
      static var testValue: CaptureRunner { CaptureRunner() }
  }
  
  extension DependencyValues {
      var captureRunner: CaptureRunner {
          get { self[CaptureRunnerKey.self] }
          set { self[CaptureRunnerKey.self] = newValue }
      }
  }
  ```

- **System APIs are wrapped in `…Provider` protocols** so tests can use fakes: `ProcessRunnerProvider` (`xcodebuild`, `simctl`, `xcresulttool`), `FileManagerProvider`, `KeychainProvider`, `FontRegistryProvider`, `AppStoreConnectProvider`, `UbiquityProvider` (the iCloud library) and `ClockProvider`. New code that touches a system API follows this pattern.

### The capture kit (`Sources/`)

- **StagehandModel:** `DeviceClass` (with the layout fallback chain `duoOuter` → `duoInner` → `pad`, which only the format 3 migration uses now; templates never borrow), `DeviceTarget` and `DeviceTable` (`Resources/devices.json`, loaded as `DeviceTable.standard`; `classify(width:height:)` accepts either orientation), `Shot` (schema 1, ISO 8601 dates through `Shot.makeEncoder()`/`makeDecoder()`), `ShotAttachment` (the `stagehand.<capture ID>.<name>` and `.meta` attachment names, shared with the importer), `Quirk` (the quirks table, keyed on model identifier and runtime; the Duo is `iPhone19,4`) and `RuntimeVersion`. `DeviceClass` is `CodingKeyRepresentable`, so `[DeviceClass: T]` encodes as a JSON object.
- **StagehandScene:** `StagehandScene` reads the scene and launch arguments, with injectable `environment` and `arguments` for tests.
- **StagehandCapture:** the logic is plain functions (`DisplayChooser`, `CGImage.isBlank()` on a 32 × 32 copy, `CapturePipeline.process`, `Expectation`, `FolderLayout`/`FolderOutput`, `CaptureEnvironment`). The XCTest side (`XCTest/`, behind `#if canImport(XCTest)`) is `Stagehand.configure` (a lock-protected global, so `class func setUp()` can call it), both `capture(scene:named:...)` overloads and `Readiness`. iOS and watchOS capture every `XCUIScreen` (falling back to `app.screenshot()` if none are listed), and macOS the app's first window. When the runner sends `STAGEHAND_APP_LANGUAGE` and `STAGEHAND_APP_REGION`, the app is launched with `-AppleLanguages` and `-AppleLocale` (`CaptureEnvironment.languageArguments`).

### The app's core (`App/Packages/StagehandCore`)

- **Model** (`Model/`): `Varying` (`set(_:for:scope:)` routes an edit to the override when the class has one; `override(for:)` makes one that stays until an edit makes it equal again), `Localized` text with the fallback chain and per-locale overrides (`setText`, `overrideText`, `revertText`; an override only holds the locales it changes), `Style` (shown as the Template Set), `Template`, `TemplateLayout`, `TextPlacement` and `DevicePlacement` (both placed by a `BoxAnchor`, one of nine points, at a position in fractions of the canvas; text has a width, and its height is the lines it wraps to at its font size; a device rotates and scales around its anchor), `Glow` (a blur of the device's silhouette), `Project` (format 3), `ProductPage`, `ShotSet` (a computed lineup), `Slide`, `AppLink` (with optional schemes and test targets per platform), `SimulatorSpec`, `BaseStyle`, and `CaptureIndex`/`CaptureRecord`/`CaptureAddress`. `Project` codes `slides` by hand as an object keyed by the ID's string, since `[UUID: T]` encodes as an array. Fonts are PostScript names, and `system-<weight>` names use the system font.
  - **Templates** (`Template.swift`): a `Template` has a `TemplateID` (format 2's `VariantID` renamed, so `straight`, `tilted` and `zoomed` kept their IDs; new ones are UUID strings), a name, extra element definitions (`TemplateElement`: text in the Primary or Secondary text style, a device showing a capture, or an image from `assets/`) and a `TemplateLayout` per class. A layout places the three standard elements (`StandardElement`: they can be hidden on a class, never deleted, so a slide's text and capture carry across templates), and the extra elements that show on that class (`extras`, keyed by `ElementID`). `ElementRef` names any element (`.primary`, `.secondary`, `.device`, `.extra(id)`) and `ElementPlacement` is any element's placement. `Style` encodes `templates` as an object keyed by ID plus `templateOrder`, so three-way merges see each template on its own. `Style.resolvedTemplate(_:for:)` falls back to the first template with a layout for the class; nothing borrows another class's layout (format 2's Duo-from-iPad fallback is gone). Each template has a `TemplatePlaceholder` (primary and secondary text): the template editor draws it (`placeholderSlide`) and never a slide's text or capture, at the same text size as every slide, and a new slide starts with it. `placeholder` was added after format 3 and decodes with a default when missing, so it needed no format bump.
  - **Slides:** `template: Varying<TemplateID>` (a slide can use Straight on iPhone and Zoomed on iPad), `excludedDevices`, `detachments: [DeviceClass: Detachment]` (a slide's own placements per element; `setTemplate(_:for:scope:)` clears a class's detachment when its template changes) and `extraContent` (`ElementContent` for extra elements, by element ID).
  - **Projects:** `devices`, `targets` (export sizes), `slideOrder` and `productPages`. `sets` computes the lineups: the main one (`ShotSet.mainID`, "App Store") and one per custom product page; `updateSet(id:_:)` writes a lineup's changes back. `slides(in:on:)` skips slides that are off for a device. `addDevice(_:includeExistingSlides:)` and `removeDevice(_:)` keep slides' text and captures.
- **Fixtures** (`Fixtures/`): `Project.fixture()` (TrekPoint's three slides on iPhone and iPad, the second using Tilted on iPhone), `Style.fixture()` (Straight for iPhone, iPad, Watch and Mac, Tilted for iPhone and iPad, Zoomed for iPhone), `Project.empty(devices:style:)` (a new document: no slides, iPhone by default, a blank template set), `Project.newSlide(title:template:locale:)`, `Style.blank(for:)` (one Untitled Template), the built-in `StarterTemplateSet`s (Dark Glow, Light and Clean, Bold Color, each with a layout for every class), `Template.similarClasses(to:)`/`blankLayout(for:)`/`completeLayouts(for:)`, and `Date.sampleDate`. They're in the library, not the tests, so previews and New Project use them.
- **Resolver** (`Resolver/`): `Resolver.resolve(ResolveRequest)` returns a `ResolvedScene` in absolute pixels, with `SceneFlag`s for every fallback (`templateFallback`, `missingLayout`, `missingImage`, and the capture and text ones). `Resolver.layout(for:style:device:)` is the template layout a slide uses on a class with its detachment laid over it; the canvas uses it too. The scene's `device` is the Main Device (`nil` when hidden), each `ResolvedDevice` carries its own glow, and `extras` are the template's extra elements (`ResolvedElement`: text, device or `ResolvedImage`), with `frame(of:)` and `elements` for snapping. Images are `ImageRef`s (a capture's includes its revision; `asset:` for images), so the scene is `Hashable` and caches key on it. Bezels come in as a `BezelCatalog`, each font's line height (measured outside, by the text measurer) in `lineHeights`, and each asset's pixel size in `assets`. `Resolver.deviceCenter`/`devicePoint` convert between a box's anchor point and its center.
- **Text** (`Text/`): text is always drawn at its text style's size (there's no auto-fit) and wraps to as many lines as it needs at its box's width. The resolver is pure, so `TextWrapping.resolve` resolves once, measures how many lines each text element wraps to (`TextMeasurer`; `SwiftUITextMeasurer` lays out SwiftUI `Text` through `ImageRenderer`, cached), and resolves again with `ResolveRequest.lineCounts`, so each box is exactly as tall as its text and grows away from its anchor. `ProjectCoordinator` resolves every scene (cells, the canvas, templates, thumbnails and exports) this way. The renderer lets text take its full height, so a line is never cut off; a single word wider than its box breaks across lines. Files from before this have `lineLimit`, `autoFitMinimum` and `autoFitScope`, which are ignored.
- **Rendering** (`Rendering/`): `SceneView` (pure SwiftUI; draws the background, extra images and devices, the Main Device's glow and device, primary and secondary text, then extra text), `SceneRenderer.render`/`exportPNG` (flattened onto an opaque sRGB context), `ImageStore` (decodes on demand), `ThumbnailCache` (keyed on the scene and scale) and `ProjectExporter` (`<locale>/<target ID>/<NN>-<slug>.png`, numbered per device so a slide that's off leaves no gap, inside `<page name>/` for a custom product page).
- **Documents** (`Documents/`): `ProjectDocument` uses SDK 27's `Document` protocol with `FileWrapperDocumentReader`/`Writer`. `ProjectPackage` reads and writes the package (`project.json`, `fonts/`, `captures/`, `assets/` and `bezels/`, the pinned bezels as `<id>.png` and `<id>.json`), and reuses a capture's previous file wrapper when its revision hasn't changed, so autosave doesn't rewrite every PNG. `FormatMigration.decode` refuses a newer `formatVersion` and runs migration steps on older JSON. `ProjectContents` (everything in the package, embedded bezels included) is also the unit each undo step restores; both documents store each part in a property of its own, so a new part needs adding to `EditableDocument.contents` and both documents. Format 2's migration (`StyleMigrations.anchorPlacements`) turns format 1's text frames into anchored positions. Format 3's (`ProjectMigrations.lineups`, `StyleMigrations.templates`/`slide`) turns sets into devices, one order (every non-page set's slides, in order) and product pages, with each slide off for the devices no set it was in had; turns each variant into a template (the layout's text placements, or the variant's own), copying a borrowed layout into each class the project uses; renames `variant` to `template`; and turns each nudge into a detached device placement. `StyleDocument` (`.stagehandstyle`, format 3 too: `previewDevices`, `previewTargets` and `previewSlides` in order, plus `bezels/`) presents a style as `ProjectContents` (`StylePackage`), so both documents conform to `EditableDocument` and share the editor; `ProjectCoordinator.document.kind` hides export, uploads and capturing for styles.
- **Coordinators** (`Coordinators/`): `ProjectCoordinator` owns the selection (including `templateID`, which puts the canvas in the template editor), every edit (`edit(_:_:)` registers one undo step; `beginGesture`/`endGesture` fold a drag into one), the contact sheet state, issues, rendering access (`canvasScene`: the template editor's preview, with the first slide that uses the template or sample text, or the selected cell) and export. A project with no slides opens on its first template. Its template, detach, device and bezel intents live in `ProjectCoordinator+Templates.swift`: adding (blank, with a layout for every project device, or duplicating), renaming, reordering and deleting templates (never the last; its slides move to the first remaining), a class's layout from another class's or blank, extra elements, showing and hiding elements per class, bezels per element, slides from a template at an index, extra content, `requestDetach`/`detach`/`reattach`, devices and custom product pages. `CanvasCoordinator` turns drags, handle drags, trackpad rotation and pinch, arrow keys and the inspector's Arrange fields into placements for any `ElementRef`: in the template editor into the template's layout, and on a slide into the slide's detachment, but only once the element is detached; a locked element asks (`requestDetach`) and changes nothing for the rest of the gesture. Devices and images resize in proportion around the handle opposite the dragged one, and text only from its leading and trailing edges. Drags snap through `Snapper` (the canvas's edges and center, and the other elements' edges and centers, reporting every tied guide) unless the view says snapping is off (⌘ held). `arrangement` gives the inspector the selected element's anchor point and size in pixels. It also owns the view's zoom (a multiple of the size that fits, `zoomRange` 0.1–16, so zooming out leaves room to drag past the canvas) and pan (points from the view's center, clamped so `panKeepsVisible` points of the canvas stay in view), and preview (`isPreviewing`, View › Preview ⌥⌘P, the bar's eye button, Esc to leave: no outlines, handles, guides or faded overflow, and gestures and arrow keys don't edit); `.zoom(by:around:)` keeps the point under the pointer still, and neither is an edit. `ProjectCoordinator` also saves the style to the library (with its embedded bezels), notices a newer base (`baseUpdate`), merges it (`pendingMerge`), embeds an installed font when one is chosen (`.useFont`), and makes New Project from This's contents (`derivedProject`: the template set, devices and embedded bezels, and optionally the slides in order). `CaptureRunCoordinator` (Mac) drives runs and imports captures with undo, `AppLinkCoordinator` (Mac) builds the app link, and `LibraryCoordinator` manages bezels (Apple's list, downloads with progress, the pending license), lists library styles, and pins new projects' bezels (`pinningBezels`).
- **Bezels** (`Bezels/`): `BezelDetector` flood-fills from the center (refusing a fill that reaches the image's edge), and `BezelLibrary` keeps `<id>.png`, `<id>.json`, `defaults.json` and `sources.json` (each Apple disk image's installed version) in the library's `Bezels/`. An imported bezel is never overwritten: the same image again returns it, and an updated image with the same name gets an ID ending in part of its checksum. A class with only one bezel uses it by default, and Library Default (`.matchTarget`) without a default draws `BezelCatalog.bestBezel` (closest screen shape within 3%, then the default, then the highest generation, then the closest shape). Masks are found again on load, not stored. `BezelSource` lists Apple Design Resources' `Bezel-*.dmg` links with the classes each product's name maps to, through `BezelDownloadProvider` (`page`, `version` from `ETag`/`Last-Modified`, and `download` with progress). `BezelDownloader` downloads into Caches, reads the license with `hdiutil udifderez` without mounting, and after Agree mounts with `yes | hdiutil attach -readonly -nobrowse` (through `/bin/sh`, the path passed as an argument), imports every PNG it finds outside hidden folders (skipping landscape images for upright devices, and images without a screen; a Duo image's name says which display, or the closest screen shape decides), detaches and deletes the image. `BezelPinning` pins the best bezel for new layouts and new projects' Library Default layouts, and embeds pinned bezels in the document. `BezelCatalog.newerBezel(than:)` finds a newer one (the same product line with a higher generation, or the same model and color imported later), which is only offered: Update Bezel… shows both and `BezelInfo.changes(to:)` (the screen's shape, the frame's size) before pinning the new one.
- **Library** (`Library/`): `StyleLibrary` keeps `.stagehandstyle` packages in the library's `Styles/` through `FileManagerProvider`, saving a style as new or as the next version of its ID. `StyleMerge` (`Merge/`) is a three-way merge over flattened JSON paths, with `Varying` overrides as their own paths and fills and bezel choices merged whole.
- **Fonts** (`Fonts/`): `FontRegistryProvider` registers a document's fonts by URL (skipping fonts already installed, which would fail as duplicates) and lists every installed family (`availableFamilies`, hidden `.`-prefixed faces left out).
- **Captures** (`Captures/`): `CaptureImporter` classifies dropped images by size, taking the key from the cell or the file name. A file dropped on the contact sheet whose name's key no slide uses is refused (`noMatchingSlide`) rather than stored where nothing shows it, and a drop on the canvas is the selected slide's capture for the class it shows (`.importCapturesToCanvas`). Capture › Import Screenshots Folder… (`.importScreenshotsFolder`, destination `.folder`) imports every image under a folder (FlaskMaster's `AppStoreScreenshots/`, TrekPoint's `Source Images/`) keyed by file name, keeping keys no slide uses yet, and the Slide inspector's Capture Key menu (`captureKeys(on:)`) lists every key there are screenshots for. The grid's drop destination takes files and template drags as one `SheetDrop`, files first.
- **Runner** (`Runner/`, Mac only): besides the kit's `stagehand.` attachments, the import takes plain screenshot attachments (`AttachmentManifest.plainScreenshots()`: images not tied to a failure), keyed by their name slugged (`01-level`, `1-terrain-made-clear`) and classified by size, which is how FlaskMaster (MJScreenshotTesting's `ScreenshotTestCase`) and TrekPoint (its own `ScreenshotTestCase`) work without the kit. Tests always run with `-parallel-testing-enabled NO`. `RunPlan.make` makes one pass per class and locale, ordered by developer directory and class, with the Duo's outer display before its inner one (`.unfolded`, which prompts). `CaptureRunner` builds once per developer directory and platform into per-project derived data in Caches, prepares "Stagehand <target>" simulators (the Duo's two classes share "Stagehand iphone-duo"), runs `test-without-building` with `TEST_RUNNER_STAGEHAND_*`, retries once after rebooting on "Busy", and imports with `xcresulttool`. Each platform builds with its own scheme when the link names one (`RunContext.scheme(for:)`), and the app's language and region go along as `TEST_RUNNER_STAGEHAND_APP_LANGUAGE`/`_REGION`. `LiveProcessRunner` cancels by interrupting `xcodebuild`, which ends its children.
- **App Store Connect** (`AppStoreConnect/`): `AppStoreConnectToken` (ES256, raw signatures, at most 20 minutes), `AppStoreConnectTokenCache`, `AppStoreConnectClient` over an `HTTPTransport`, `UploadPlanner` (keeps screenshots whose MD5 matches; `keepsOrder` adds and replaces without reordering) and `UploadCoordinator`, whose `plan()` only reads and whose upload runs only on `.confirmUpload`. Mac targets plan against the macOS version and the rest against iOS's. A custom product page plans against that page's editable version's localizations (`ASCLocalization.Kind.customProductPage`).
- **Localization** (`Localization/`): `StringCatalog.export`/`importCatalog`, with device variations for overrides and `.duoOuter`/`.duoInner` keys of their own. Extra text elements export as `<slide slug>.<element name slug>` (`extra-` in front of a name that's a role's or class's).
- **Validation** (`Validation/`): `ProjectValidator.setIssues` for the project-level checks (10 slides per device, a device no template has a layout for, a template a slide uses without a layout for a device, required sizes not exported). Cell flags come from each scene, and newer bezels from `ProjectCoordinator.bezelIssues`.

### The app (`App/Stagehand`)

`StagehandApp` is a `DocumentGroup` for projects (whose `makeDocument` goes through `NewProjectPicker`, in StagehandCore: only a creation that File › New Project… or the Welcome window's New Project asked for, through `requestNewProject()`, waits on the New Project window, and everything else is a document SwiftUI reads a file into; File's New items are Stagehand's own for that reason), one for styles, the Welcome window (presented at launch with `.defaultLaunchBehavior(.presented)` instead of the system's open panel, and modeled on Xcode's: a `.hiddenTitleBar` window with its title and window buttons hidden (`WelcomeWindowChrome`), its own close button, dragging by its background (`WindowDragGesture`), the icon and version, Open…, New Project with New Template Set in its menu, and the recent documents, which open on double-click or Return; Window › Welcome to Stagehand, ⇧⌘1; it closes when a document window appears), a Library window (template sets, Apple's bezels to download, or download again for a removed color, the license sheet, and the library's bezels), and Settings (the App Store Connect key). New Project (`NewProjectWindow`, through `NewProjectPicker`) picks devices (iPhone by default) and a template set: a starter, a library one, or Start from Scratch. `ProjectWindow` takes `any EditableDocument`, creates the coordinators and shows the sidebar (Templates, which drag out as `TemplateDrag` strings; the lineup's slides, which take template drops; Drafts; Lineups), the contact sheet (a "+" cell where a slide is off for a device, template drops, a banner when a device has no bezels) or canvas, and the inspector (Slide or, in the template editor, Template; Template Set; and Project tabs). On the canvas, scrolling pans and ⌘-scroll zooms (`canvasScrolling`, an `NSEvent` monitor on the Mac, since SwiftUI has no scroll wheel event), View › Zoom In/Out/to Fit (⌘+ or ⌘=, ⌘−, ⌘0) reach the canvas through the `canvasCoordinator` focused value, the bar shows the zoom, and the scene is drawn a second time unclipped and faded underneath, so what's dragged past an edge stays visible (`SceneView(clipsToCanvas: false)`; exports stay clipped). Link App's Choose… takes a project, a workspace or the folder holding one (`AppLinkCoordinator.xcodeProject(for:fileManager:)`). Locked elements show a lock badge, a move on one asks to detach through an alert (Edit Template Instead, Detach This Slide, Cancel), and the bar says which template is being edited. `ArrangeSection` (shared by the Slide and Template inspectors) shows the lock and Detach This Slide, or Reset to Template. The Template inspector adds layouts per device (Start from <class>'s Layout or Start Blank), elements, text boxes, and the bezel picker with the Newer Bezel notice and `UpdateBezelSheet`. Inspector rows go through `InspectorRow` (a fixed label column, a control that fills the middle, and a badge slot), with `VaryingRow` adding the link badge, `PairField`, `NumberField`, `SliderField` (a slider and a field to type the number in, shown through a `Display`: a percentage by default, or points for text size), `AnchorGrid` and `FontMenu` in `InspectorComponents.swift`. The canvas measures every gesture in a named coordinate space (`CanvasView.space`), which is what keeps handles from jittering as they move. Sheets cover issues, linking, the run log, uploads (with Keep App Store Connect's Order), merging, New Project from This (a `fileExporter` of a new `ProjectDocument`, then opening it) and the search preview. Platform-only modifiers are wrapped in `View+Platform.swift` (`pointerHoverEffect`, `trackingModifiers`, `radioPickerStyle`). Menu commands (including the Template menu: New Template, Edit Slide's Template ⌥⌘T, Back to Slide ⌘⎋) reach the frontmost window through `FocusedValues` (`projectCoordinator`, `captureRunCoordinator`). Views that show run status take a `RunStatusSource`, so the iPad build compiles them without the runner. The project uses file-system-synchronized groups; `Info.plist` and `Stagehand.entitlements` are excluded from the target's membership. `Info.plist` declares both document types as an Editor. The entitlements are iCloud Documents with the `iCloud.com.mazjap.Stagehand` container.

### The fixture app (`Fixtures/StagehandFixtureApp`)

One SwiftUI source (`StagehandFixtureApp/`) with a dark and a light scene, built as an iOS 17 app, a watch-only watchOS 10 app and a macOS 14 app (which sizes its window to `StagehandScene.requestedWindowSize`), each with a screenshot UI test target that shares `StagehandFixtureAppScreenshots/` and its own scheme (`StagehandFixtureApp`, `StagehandFixtureWatch`, `StagehandFixtureMac`). It greets in the test language, so captures in two languages differ. It depends on the repository root by path.

## Testing

Test targets:

- **`StagehandModelTests` and `StagehandCaptureTests`** (Swift Testing, `swift test` at the root): the device table (no size in two targets, every class has a target), classification, choosing the displayed screen, blank detection, quirks, metadata coding, and folder layouts. The kit's logic takes plain values and `CGImage`s, and the XCUITest calls around it stay thin, so none of this needs a simulator.
- **`StagehandCoreTests`** (Swift Testing): `Varying` and `Localized` resolution, fallback chains, the resolver, templates and detaching (`TemplateTests`, `CanvasCoordinatorTests`), text wrapping (with a fake text measurer), three-way style merges, document coding and format migrations (format 2's fixture, `formats/project-v2.json`, has to draw every cell where format 2's resolver did, as recorded in `project-v2-geometry.json`), Apple's bezels (a trimmed copy of the page in `bezels/design-resources.html`, the downloader's commands with a fake process runner, pinning and newer bezels), String Catalog round trips, bezel screen detection, export (exact sizes, no alpha, file names), the runner's command lines and result import (a fake process runner, with `xcresulttool` output recorded from a real run as fixtures), and the App Store Connect client (a fake transport, and JWT signing checked against the key's public half).
- **Renderer snapshots** (in StagehandCoreTests, with [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)): fixture projects rendered at a small scale. References are recorded on macOS 27, and the suite is skipped (not failed) on anything else. Fixture fonts and the synthetic bezel live in the tests' resources, so snapshots don't depend on what's installed.
- **`StagehandTests`** (app-hosted on the Mac): coordinators wired together, and the app's `Info.plist` declaring every document type.
- **`EndToEndTests`** (opt-in with `STAGEHAND_E2E=1`): the runner builds and drives `Fixtures/StagehandFixtureApp`'s screenshot tests on a real simulator and imports the captures.

Rules:

- **Every bug fix must include a new test that fails without the fix and passes with it.** Add it to the existing suite for the affected type, or create `<TypeName>Tests.swift`. Prefer a unit or integration test. Mark it with a `/// Regression test: …` doc comment explaining the bug. If the logic lives in a view, move it into a testable coordinator or helper first. Changing text isn't a bug fix and gets no test.
- Every Swift Testing suite that uses dependencies is `@MainActor @Suite(.dependencies)` (import `DependenciesTestSupport`), so each test gets its own dependency cache.
- Resolve dependencies before starting an unstructured `Task` (`let runner = captureRunner`), not inside it, or tests can get a different instance than the one they check.
- For sample data, use `Project.fixture()`, `Style.fixture()` and `Date.sampleDate` (noon UTC, so formatted dates don't depend on the machine's time zone).
- Snapshot tests record a missing reference automatically and fail once, so it gets reviewed. After an intentional rendering change, delete the outdated `.png`, run the suite, **look at the new image**, and run it again to confirm it passes.
- After changing the kit, also build it for iOS and watchOS, and with Xcode-Beta (see Commands).
- Run the affected suites before calling a change done.

## Style guide

These conventions match the user's other apps (TrekPoint). Follow them.

### Whitespace and formatting

- Indent with **4 spaces**, never tabs.
- **Blank lines are indented to match the next non-blank line** (Xcode's behavior). A blank line between two statements indented 8 spaces contains 8 spaces, not zero. Only blank lines at file scope are truly empty. The Edit tool can strip this whitespace from blank lines in `new_string`, so check `git diff` for added blank lines with no indentation. Never strip the whitespace from lines you didn't change.
- One blank (indented) line between members, and between logical groups of statements inside a function.
- Long calls may stay on one line; break them one argument per line when that reads better.

### Comments

- Use `// MARK: - Section` to organize files, and put extensions under `// MARK: - Functions` / `// MARK: - Computed Properties`.
- Use `// TODO: - Description` for known follow-ups and `// NOTE: - Description` for non-obvious explanations. Keep the `: - ` form so they show in Xcode's jump bar.
- Use `///` doc comments on non-obvious helpers, on everything public in the kit, and on anything with a warning (`/// > Warning:`).

### Swift idioms

- Managers and coordinators are `@Observable @MainActor class`. Dependencies are `@ObservationIgnored @Dependency(\.x) private var x`. In views, access coordinators through `@Bindable private var coordinator`.
- Views declare an explicit `init` and store their inputs as `private let` properties. Callbacks are named `onX` (`onIntent`, `onSelection`, `onDismiss`).
- Prefer `if` / `switch` **expressions** and implicit returns.
- Use `case let .foo(bar)` for pattern binding, not `case .foo(let bar)`.
- Use `[weak self]` in closures stored on coordinators.
- Nested types for scoped helpers, and `fileprivate` / `private struct` for view-local subviews.
- Extensions of other types go in `Helpers/Type+Topic.swift` within their module (like `CGImage+Blank.swift`).
- The app's code has no `#available` checks (its minimum is 27). The kit's code does, since it supports older systems.

### Errors and user feedback

- Throw typed error enums from managers (`ExportError`, `CaptureRunError`, `BezelImportError`). Coordinators catch them and show them: on the affected contact sheet cell and in the issues list for anything tied to a cell, and in an alert for anything that stops the work.
- Don't use `print` for error handling. Log with `Logger` (subsystem `com.mazjap.Stagehand`, a category per area: `Runner`, `Export`, `Documents`) and show the error, or throw.

### Accessibility and input

- Give icon-only buttons an `.accessibilityLabel`.
- Primary actions have keyboard shortcuts (⌘E Export, ⌘R Run Captures, ⌘D Duplicate Slide, arrow keys to nudge and Shift-arrow for 10×), so keep them when adding actions. Add `.pointerHoverEffect()` (which applies `.hoverEffect()` on iPadOS, since it's unavailable on macOS) to tappable elements for the iPad's pointer.
- Respect `accessibilityReduceMotion` for any animation.

### Previews

Every view file ends with a `#Preview`, using `@Previewable @State` for bindings and `withDependencies { … } operation: { … }` with fixture projects to seed state.

## Gotchas

These come from the design work and from TrekPoint's screenshot tests. Add to them as Stagehand finds its own.

- **App Store Connect rejects images with an alpha channel.** Exports are drawn onto an opaque context before PNG encoding. A test checks it.
- **`ImageRenderer` doesn't draw views backed by AppKit or UIKit,** so the renderer stays pure SwiftUI.
- **Fonts have to be registered before anything renders,** or text silently falls back to the system font. Rendering waits for the document's fonts to register.
- **Never decide anything from the kind of device.** Classify captures by pixel size (an idiom can't tell a Duo's outer display from its inner one), and lay out the editor from size classes and measured geometry, not the platform.
- **iPhone Duo simulator (Xcode 27.1, iOS 27.1):**
  - It boots folded, and there's no `simctl` or XCTest way to fold or unfold it. It has to be done with Device Hub's buttons (Device Hub replaced the Simulator app in Xcode 27), which is why the runner has a manual unfold step.
  - `XCUIScreen.screens` lists both displays. The inner one is listed but black while folded, and `XCUIScreen.main` is the cover display even when open. So the kit captures the largest screen that isn't blank.
  - Inner display screenshots come back upside down (the `duo-inner-rotated-180` quirk). Quirks are keyed on the simulator's model and runtime, so a fixed runtime isn't flipped back.
- **A destination given by device name alone only looks at the newest runtime.** The runner always uses simulator UDIDs.
- **An `.xctestrun` belongs to the Xcode that built it.** Don't run one with a different developer directory.
- **Settings reach the test runner as `TEST_RUNNER_`-prefixed environment variables** given to `xcodebuild`, which strips the prefix. Anything else set on `xcodebuild` doesn't reach the tests.
- **`xcodebuild` fails on a package macro that Xcode hasn't been told to trust** ("must be enabled before it can be used"), including after the package updates, where Xcode would ask again. Stagehand doesn't skip that check; the user trusts the macro by building the app once in Xcode. A failed build's message leads with its `error:` lines (`CaptureRunError.buildFailureSummary`), since the log ends with the target dependency graph.
- **The linked scheme's test action has to include the screenshot test target.** TrekPoint's `TrekPoint` scheme doesn't; `TrekPointScreenshots` does.
- **`xcresulttool`'s output format can change between Xcode versions.** The import is pinned by fixture tests. Refresh the fixtures after each Xcode update.
- **Apple Watch screenshots have to be the same size in every localization.** Validation checks it.
- **App Store Connect's locale codes don't always match an app's** (`de-DE` and `de`). Go through the project's locale map.
- **App Store Connect's JWTs need the signature's raw 64-byte form** (`signature.rawRepresentation`), not CryptoKit's DER form, which App Store Connect rejects as unauthorized.
- **Use `url.path(percentEncoded: false)` with `FileManager`,** not `url.path()`, which percent-encodes spaces (like in "Application Support" and "Pixelmator Files") so files never seem to exist.
- **Never show an alert (or change other observed state) while a view's `body` is being computed.** It redraws the view, and if the same code runs again it loops forever. Thumbnails and text measuring render inside `body`, which is fine only because their caches aren't observed.
- **Xcode exports attachments with `_<n>_<UUID>` inserted before the name's last dot-separated part** (Xcode 27.1): `stagehand.<ID>.dark-scene` comes out as `stagehand.<ID>_0_<UUID>.dark-scene`, since Xcode treats `.dark-scene` as an extension. `AttachmentManifest.stripExportSuffix` removes it. Capture keys can't contain dots.
- **Only one target in the app project links StagehandCore.** When two targets link the same static package product, Xcode makes it a dynamic framework, and the app can't link StagehandModel's symbols. `StagehandTests` links nothing and resolves against the host app through `BUNDLE_LOADER`.
- **`@State` is a macro in SDK 27.** Declare it without an initial value and assign it in `init`, after the other stored properties.
- **A project's `[UUID: T]` dictionaries encode as arrays,** since `UUID` isn't `CodingKeyRepresentable`. `Project` codes `slides` by hand; do the same for any new dictionary keyed by an ID.
- **iCloud Documents needs both `com.apple.developer.icloud-services` (`CloudDocuments`) and `com.apple.developer.ubiquity-container-identifiers`.** Checking only the container in Signing & Capabilities leaves the services empty. Without iCloud, the library falls back to Application Support/Stagehand/Library.
- **`-testLanguage` and `-testRegion` only reach the test runner, not the app it launches.** The kit launches the app with `-AppleLanguages` and `-AppleLocale` from `STAGEHAND_APP_LANGUAGE`/`_REGION`. And `Locale.current` only offers languages an app is localized for, so the fixture reads `Locale.preferredLanguages`.
- **SwiftUI and Core Text already have types named `Anchor` and `AnchorPoint`,** so the nine-point anchor is `BoxAnchor`.
- **A `@MainActor` protocol on a document class isolates the whole class,** which breaks its `Document` conformance. `EditableDocument` is nonisolated for that reason.
- **ISO 8601 dates drop fractional seconds,** so a `Date()` doesn't survive a save. Values that must round-trip (like a new style's `importedAt`) use whole seconds.
- **Registering a font that's already installed fails with a duplicate-name error,** so a document's embedded copies of installed fonts aren't registered again.
- **Swift Testing runs tests in parallel,** so `EndToEndTests` is `.serialized`: two simulators booting at once can crash CoreSimulator.
- **SwiftUI calls `makeDocument` for every document, opened and restored ones included,** then reads the file into the instance, and its configuration's `fileURL` is often still `nil` for an opened file. Waiting on the New Project window for an opened file left its window blank, so only an explicitly requested creation waits (`NewProjectPicker.requestNewProject()`). Each document keeps the configuration (`fileConfiguration`), and `ProjectWindow` notes its URL with `NSDocumentController`, which fills the Welcome window's recents and File › Open Recent.
- **A number field commits when it loses focus,** which can come after a click has already changed the selection, so its value landed on the newly selected template, slide or element. `ProjectCoordinator.commitPendingEdits` (the app's `PendingEdits.commit`, which ends the field editor's editing) runs before every intent that changes the selection, and before the canvas selects another element.
- **Every `DocumentGroup`'s type has to be in `CFBundleDocumentTypes`,** not only exported. The style type was missing, and the launch panel offered no way to make a project. `DocumentTypeTests` checks it.
- **Apple's bezel disk images carry a license agreement,** so `hdiutil attach` stops to ask. Stagehand shows the license (read with `hdiutil udifderez`, which doesn't mount) and only attaches after Agree, answering the prompt with `yes`. Never accept it without the user.
- **Apple's bezel PNGs are the whole device in one image:** frame, side buttons, and the Dynamic Island inside the transparent screen, so the bezel draws above the capture. The Photoshop files beside them have no separate layers for those (one Hardware smart object and a Screen layer).
- **Apple's bezel downloads are large** (7 MB to 450 MB each), so they're one product at a time, on demand, with progress.
- **Projects embed the bezels they pin.** A bezel pinned without being embedded only draws while the library has it; `ProjectCoordinator` embeds through `BezelPinning.embed` in the same edit that pins.
- **In SDK 27, `dropDestination(for:)`'s action returns `Void` on a view** (and on `ForEach`), so a helper returning `Bool` needs `_ =`.
- **`UTType(filenameExtension:)` assumes a data file,** so for a package like `xcodeproj` it makes up a dynamic type nothing conforms to, and the open panel greys every project out. Pass `conformingTo: .package` (`AppLinkCoordinator.projectTypes`). `AppLinkCoordinatorTests` checks a real folder.
- **`.windowStyle(.plain)` makes a borderless window,** which can't become key (no keyboard), has no shadow, and doesn't drag by its background. The Welcome window uses `.hiddenTitleBar` with its buttons hidden instead.
- **Stagehand never restores the last session's windows** (the user wants the Welcome window alone at launch). `.restorationBehavior(.disabled)` doesn't stop a `DocumentGroup`'s documents coming back, so `StagehandApp` sets `NSQuitAlwaysKeepsWindows` to `false` in the app's domain, which overrides the system setting.
- **The user runs Amethyst, a window tiler,** which resizes new windows as they open. Anything on the canvas that depends on the canvas's size mustn't change the canvas's size (the bar stays one line), or the two fight in a loop.
- **AppKit's `cacheDisplay` doesn't draw SwiftUI blurs,** so the glow is missing from window snapshots taken that way. `ImageRenderer` (exports, thumbnails and snapshot tests) draws it.
