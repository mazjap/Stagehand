# Stagehand: Plan

Stagehand makes App Store screenshots for Jordan's apps (TrekPoint, Flask Master, and the ones after them). Today, each app's screenshot UI tests save raw captures, and every finished screenshot is laid out by hand in Pixelmator Pro, once per app and device size, with that app's own colors, fonts and positions. Stagehand lays a project out once, renders every App Store Connect size from it, and gets the raw captures by driving those same UI tests through a shared Swift package.

This file is the design. TASKS.md is the work list, in order. CLAUDE.md describes what's actually built: when part of this plan ships, its details move into CLAUDE.md's Architecture section and are trimmed from here.

## Goals

- One layout per device class renders every App Store Connect size in that class.
- Text is edited once and shows on every device that shares it, with per-device overrides where a device needs something different.
- A look (a style) can be reused across apps, and a new style can be designed without any app attached.
- Raw screenshots come from each app's existing screenshot UI tests, through one shared capture kit instead of a helper copied into each app.
- Localization is planned from the start. Listings are English only today, but the apps are localized into about seven languages.
- Later, screenshots upload straight to App Store Connect.

## Non-goals

- Publishing Stagehand. It's a personal tool that's never submitted to the App Store, which is what lets it run Xcode's tools without App Sandbox.
- iPhone. Stagehand runs on the Mac now, and on an iPad later.
- App previews (videos). TrekPoint's flyovers stay in TrekPoint (`AppStoreVideos`).
- Google Play.

## Platforms and repository layout

- **The app** is SwiftUI, multiplatform: macOS 27 and iPadOS 27 minimum, native on both (not Mac Catalyst or Designed for iPad), Swift 6 language mode. It's built and used on the Mac. There's no iPad yet, but the iPad build has to keep compiling. Capturing runs only on the Mac, since it launches `xcodebuild` and `simctl`. An iPad would open projects from iCloud Drive and edit, export and upload them.
- **The capture kit** is a Swift package that the apps' screenshot UI test targets and app targets depend on. Its platforms follow the oldest app that uses it (TrekPoint supports iOS 17), not Stagehand's: iOS 17, macOS 14 and watchOS 10 to start. It has no dependencies.

```
Stagehand/                         git repository root
├── Package.swift                  the capture kit (apps add this repository by URL)
├── Sources/
│   ├── StagehandModel/            device classes, devices.json, capture metadata, classifier
│   ├── StagehandCapture/          for UI test targets: capture(scene:named:...), displays, quirks, outputs
│   └── StagehandScene/            for app targets: the scene being staged, "is capturing"
├── Tests/
│   ├── StagehandModelTests/
│   └── StagehandCaptureTests/     logic tests with fixture images (no XCUITest)
├── App/
│   ├── Stagehand.xcodeproj
│   ├── Stagehand/                 app target: views, coordinators, document types
│   ├── StagehandTests/            app-hosted tests
│   └── Packages/StagehandCore/    documents, resolver, renderer, bezels, capture runner, App Store Connect client
├── Fixtures/StagehandFixtureApp/  a tiny iOS app with a screenshot UI test target, for end-to-end tests
├── CLAUDE.md
├── PLAN.md
└── TASKS.md
```

The kit sits at the root because Swift Package Manager reads the `Package.swift` at the root of a repository's URL. The app's heavier code lives in its own local package (`StagehandCore`, which depends on the root package by path), so apps that add the kit never resolve the app's dependencies.

## Concepts

| Term | What it is |
|---|---|
| Device class | `phone`, `duoOuter`, `duoInner`, `pad`, `mac`, `watch`. Templates have a layout per device class, and captures, bezels and overrides are per class too. |
| Device target | One App Store Connect screenshot slot and its accepted pixel sizes (like "iPhone with Dynamic Island, large display"). Several targets can share a device class. |
| Template set (`Style` in code) | A project's look: color tokens, a background, the Primary and Secondary text styles, and its templates. It can be saved to the library and reused. The UI says "Template Set"; the code, the file type (`.stagehandstyle`) and the library folder keep the name `Style`, since renaming a file type breaks saved files. |
| Template | A named arrangement, like "Straight", "Tilted" or "Zoomed", with its own layout for each device class: where Primary Text, Secondary Text and the Main Device sit, the device's bezel, and any extra elements. |
| Element | Something a template places. Every template has the three standard elements (Primary Text, Secondary Text and Main Device), which can be hidden but not deleted. Templates can add any number of extra text, device and image elements. |
| `Varying<T>` | A value that's shared across device classes unless a class overrides it. Everything that's "linked by default" is a `Varying`. |
| Project | One app's screenshots: an embedded copy of a template set, its devices, a pool of slides in one order, captures, locales, and the link to the app's Xcode project. |
| Slide | One screenshot idea ("Read the Land"): its text, the capture in each device element, which template it uses (per device, through `Varying`), and which of the project's devices it's on. |
| Detachment | A slide's own placement of an element on one device class, made only after confirming that the slide stops following its template there. |
| Lineup (`ShotSet` in code) | An ordered list of slides on the project's devices. The project's own order is the main lineup, which uploads to the product page. A custom product page is another lineup. Lineups are computed from the project, not saved. |
| Capture | A raw screenshot from a UI test, keyed by capture key, device class and locale. |
| Library | Template sets that aren't tied to a project, plus bezels, kept in Stagehand's iCloud Drive folder. |
| Contact sheet | The main view: a grid of slides by device targets with a thumbnail in every cell. |

## Built

These parts of the design shipped, and are described in CLAUDE.md's Architecture section: the data model and its resolution rules, templates (with locked slides, detachments and extra elements), devices added one at a time with one slide order, lineups in place of sets, the device table (`devices.json`), rendering, text that wraps at its style's size, bezels (downloaded from Apple Design Resources, pinned and embedded), project and style documents (format 3), the Welcome window and New Project flow, the library and its flows (new projects from template sets, saving template sets, pulling changes, New Project from This), the editor's search preview, the capture kit, the capture runner, localization, and App Store Connect uploads (including custom product pages, and keeping App Store Connect's order). What's below is still to build, or still to decide.

## Templates, devices and bezels

Built (CLAUDE.md's Architecture describes them), except what only a person can check:

- **The Welcome window** at launch, and New Project from it, by hand on the Mac.

## The capture kit

### Moving the apps to the kit

- **TrekPoint** (`TrekPointScreenshots`, in TrekPoint's repository and under its CLAUDE.md's git workflow): replace `ScreenshotTestCase.capture`'s launching, waiting, display choosing and saving with the kit. Keep `-ui-testing -app-store-preview`, the scene JSON in `TREKPOINT_SCREENSHOT_SCENE`, readiness on the render report's `staged: true`, the 9-second settle, and the folders under `src/Pixelmator Files/AppStoreConnect/Source Images/` (`iPhone`, `iPhone Duo`, `iPhone Duo Closed`, `iPad`) through a custom folder layout. The status bar stays hidden by the app, so its link turns off Stagehand's status bar override. TrekPoint already reads its scene itself, so only the screenshot target adds the kit (StagehandCapture), not the app target.
- **The second app** (with `capture(scene:named:waitingFor:timeout:settle:)`): replace the helper with the kit's, which has the same signature. Its folders change from idiom-based `iPhone`/`iPad` to device classes, or keep a custom layout.
- **Watch targets** use the same calls.

## The capture runner (macOS only)

Built, except for real runs against TrekPoint (both Duo displays) and running the Mac end-to-end test, which needs UI automation permission.

## App Store Connect upload

Built, except waiting for App Store Connect to finish processing uploads before reordering them.

## Milestones

The order and the work items are in TASKS.md.

1. **Repository:** the layout, the app target and packages, document types, iCloud, and dependencies.
2. **Render one app's screenshots:** the model, documents, fonts, bezels, the resolver and renderer, export, drag-and-drop import, and the contact sheet, for iPhone and iPad in English. This alone replaces Pixelmator.
3. **Capture kit and runner:** the package, the runner, the fixture app, and moving TrekPoint and the second app onto the kit. This comes early because the apps already have screenshot test targets.
4. **Sets, variants and every device:** the slide pool, shared slides, variants, the Duo (with the unfold step), the Mac, Watch, and validation.
5. **Library and reuse:** style documents, the library, promoting styles, pulling changes, duplicating sets and projects.
6. **Localization:** locale lists, the String Catalog round trip, per-locale text and captures.
7. **App Store Connect:** authentication, the client, and planned, confirmed uploads.
8. **iPad:** checking the build, touch editing, and the library through Files.
9. **Templates, devices and bezels:** the Welcome window and New Project flow, templates with locked slides and detachments, devices added one at a time, lineups in place of sets, and bezels downloaded from Apple Design Resources and pinned.

## Open questions

1. **Which iPhone size is required?** Apple's page (October 2026) lists the medium Dynamic Island display as the required iPhone size, while TrekPoint uploads 6.9-inch (1320 × 2868) screenshots. Check in App Store Connect which slots a 6.9-inch set fills before setting `isRequired` in `devices.json`.
2. **Answered (October 2026):** Apple Design Resources has an iPhone Duo bezel (`Bezel-iPhone-Duo.dmg`). Whether it has separate images for the open and closed displays is still to check on the first download.
3. **Folding the Duo from the command line:** there's no supported way from `simctl` or XCTest yet. Watch for one in each Xcode 27.x release, and drop the manual unfold step when it arrives.
4. **Answered (watchOS 27.0):** `XCUIScreen.screens` works in watchOS UI tests, so the kit captures the Watch the same way as iOS.
5. **Answered (Xcode 27.1):** `xcresulttool export attachments` treats the part of an attachment's name after its last dot as an extension and inserts `_<n>_<UUID>` before it (`stagehand.<ID>_0_<UUID>.dark-scene`). The import strips it, pinned by fixtures recorded from the fixture app. Refresh them after each Xcode update.
6. **String Catalog device variations:** is there one for iPhone Duo?
7. **Mac screenshots:** a framed window on the style's background, or a full desktop? The fixture style uses a framed window for now (`bezel: .none`, small corners, the glow).
8. **Appearance:** should light and dark be a capture dimension, like locale?
11. **The bezel images' contents:** partly answered by the iPhone 18 download (November 2026): `PNG/<model>/<model> - <color> - <Portrait|Landscape>.png` and the same in `Photoshop/` as `.psd`, for the iPhone 18 Pro and Pro Max in four colors, plus the window background in `.DropDMGBackground/`. Each PNG is the whole device in one image (frame, side buttons, and the Dynamic Island over a transparent screen), and the Photoshop files hold only a Hardware layer (a smart object whose inner file is also one flat layer, at about three times the size) and a Screen layer, so there are no separate layers to import. The iPad Pro (M5), Apple Watch Ultra 4 and iPhone Duo downloads (November 2026) follow the same pattern: the Duo's images say which display (`Inner Open Portrait`, `Outer Closed Portrait`) and import to the inner and outer classes, the iPad's come in 11" and 13", and the Watch's are named for a case and band (`AW Ultra 4 - Black + Ocean Band Translucent Black`).
9. **Names:** answered: the second app is Flask Master, through MJGameKit's MJScreenshotTesting (TASKS.md 3.13).
10. **The Duo's `ScreenshotDisplayType` values:** `devices.json` has `APP_IPHONE_DUO_OUTER` and `APP_IPHONE_DUO_INNER` as placeholders (`displayTypeVerified: false`). Check them against Apple's OpenAPI spec before uploading Duo screenshots.
