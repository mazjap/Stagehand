# Stagehand: Tasks

The work list, in order. PLAN.md has the design behind each task, and CLAUDE.md has the rules for doing it. Each task is about one branch and pull request, named after it (like `feature/device-table` for 2.1). When a task's pull request merges, check it off here, describe what it built in CLAUDE.md's Architecture section, and trim that part from PLAN.md.

"Done when" is the check that finishes a task. A task that turns up an answer to one of PLAN.md's open questions records it in PLAN.md.

## 0. Before starting

- [ ] **0.1 Find out which iPhone size is required.** In App Store Connect, check which iPhone slots a 6.9-inch (1320 × 2868) set fills, and whether the medium Dynamic Island size is really the required one (PLAN.md, open question 1).
  - Done when `isRequired` for each iPhone target in PLAN.md's device table is settled.
- [ ] **0.2 Name the second app.** Record which app has `capture(scene:named:waitingFor:timeout:settle:)` (probably Flask Master, whose screenshots have no iPhone Duo sizes yet) in task 3.13 below (open question 9).
- [ ] **0.3 Get the bezels.** Replaced by 9.6: Stagehand downloads them from Apple Design Resources itself. There's an iPhone Duo bezel (open question 2).

## 1. Repository

- [x] **1.1 Lay out the repository** as in PLAN.md:
  - The root `Package.swift`: the kit's three products (StagehandModel, StagehandScene, StagehandCapture) and their test targets; iOS 17, macOS 14 and watchOS 10; Swift 6 language mode; no dependencies.
  - `App/Stagehand.xcodeproj`: one multiplatform app target (macOS 27 and iPadOS 27, iPhone turned off), `StagehandTests`, and the `Stagehand` scheme.
  - `App/Packages/StagehandCore`: macOS 27 and iOS 27, depending on the root package by path, swift-dependencies, and swift-snapshot-testing (tests only).
  - `.gitignore`: `.build/`, DerivedData, `xcuserdata/` and `xcode-skills/`.
  - CLAUDE.md, PLAN.md and TASKS.md.
  - Done when every command in CLAUDE.md's Commands section succeeds, with placeholder tests.
  - Built without a pull request: the folder wasn't a git repository yet. Every command in CLAUDE.md's Commands succeeds except the Xcode-Beta build, since only `/Applications/Xcode.app` (27.1) is installed here.
- [x] **1.2 Set up the app target.**
  - Bundle identifier `com.mazjap.Stagehand`, and App Sandbox off on macOS.
  - iCloud Documents with the `iCloud.com.mazjap.Stagehand` container.
  - The two document types, exported as packages: `com.mazjap.stagehand.project` (`.stagehand`) and `com.mazjap.stagehand.style` (`.stagehandstyle`), both conforming to `com.apple.package`.
  - A `DocumentGroup` for projects that opens an empty project, using the approach the `building-document-based-swiftui-applications` skill recommends for package documents.
  - Done when a new project can be saved, closed and reopened on the Mac, Finder shows it as one file, and the iPad build compiles.
  - iCloud Documents is on (the user registered the container). Checking save, close and reopen by hand is still worth doing once.
- [x] **1.3 Link the Xcode skills** that CLAUDE.md lists, if they're exported.

## 2. Render one app's screenshots

The goal: TrekPoint's English iPhone (6.9-inch) and iPad (13-inch) screenshots come out of Stagehand looking like the current Pixelmator exports, from captures dropped in by hand. This alone replaces Pixelmator.

- [x] **2.1 The device table** (StagehandModel): `DeviceClass`, `DeviceTarget`, `devices.json` (as a resource) with PLAN.md's table, each target's `ScreenshotDisplayType` value and `isRequired`, and the classifier from a pixel size (portrait or landscape) to a target.
  - Done when tests show that no size is in two targets, every device class has a target, every size in the table classifies to its target, and an unknown size classifies to nothing.
- [x] **2.2 `Varying` and `Localized`**, with PLAN.md's resolution rules for text, and an override equal to the base removed.
  - Done when each rule has a test.
- [x] **2.3 The model** (StagehandCore): `Style`, `TextStyle`, `Layout`, `TextPlacement`, `DevicePlacement`, `Project`, `ShotSet`, `Slide`, and the small types they use (`NormRect`, `NormPoint`, `NormTransform`, `RGBA`, `Fill`, `FontSpec`, `Glow`, `BezelChoice`, `VariantID`, `LetterCase`). Add `Project.fixture()`, `Style.fixture()` and `Date.sampleDate`.
  - Done when every type round-trips through JSON in a test, and the fixtures build a project with an iPhone and an iPad layout.
- [x] **2.4 Project documents:** reading and writing the `.stagehand` package (`project.json`, `fonts/`, `captures/`, `assets/`), `formatVersion` 1 with a migration hook, and undo for every edit, with a drag coalesced into one step.
  - Done when tests show a project round-trips through a package, and a newer `formatVersion` than the app knows is refused with a clear error.
- [x] **2.5 Fonts:** add a font file to a project's `fonts/`, register the document's fonts on open through `FontRegistryProvider`, and hold rendering until they're registered. The font picker lists the document's fonts.
  - Done when a test with a fixture font shows text renders in that font, never the system font.
- [x] **2.6 Bezels:** import a bezel PNG, find its screen by flood fill from the center, write `bezel.json`, keep bezels in the library's `Bezels/` folder (through `UbiquityProvider`), choose a default per device class, and draw a plain rounded frame (flagging the cell) when one is missing.
  - Done when a test with the synthetic bezel finds its screen rect within 1 px and its mask matches.
- [x] **2.7 The resolver:** `resolve(...) -> ResolvedScene`, as a pure function.
  - Done when tests cover the text, layout, variant and capture fallbacks (each flagged), nudges, and frames that scale in proportion across every target in a class.
- [x] **2.8 Auto-fit:** a `TextMeasurer` protocol (the live one measures SwiftUI `Text`; tests use a fake), the largest size that fits every slide in a set for each class and locale, and an overflow flag below the minimum.
  - Done when tests show slides in a set share one size, and a long headline is flagged instead of shrinking past the minimum.
- [x] **2.9 The renderer:** one SwiftUI view that draws a `ResolvedScene` in PLAN.md's order (background, glow, capture clipped to the bezel's screen, bezel, primary text, secondary text).
  - Done when snapshot tests of the fixture project pass for iPhone and iPad, straight and tilted, including a device that runs off the canvas's edge.
- [x] **2.10 Export:** `ImageRenderer` at the target's exact pixel size, flattened onto an opaque context, PNG, written as `<listing locale>/<target ID>/<NN>-<slide slug>.png` into a chosen folder. ⌘E exports.
  - Done when tests show each export's exact size, no alpha channel, and its file name.
- [x] **2.11 Drag-and-drop captures:** drop PNGs onto a cell (which sets their capture key and device class) or onto the contact sheet (which classifies them by size and takes the capture key from the file name). Store them in `captures/` with an `index.json` entry.
  - Done when tests show a dropped image is classified, and one whose size isn't in `devices.json` is refused and listed as an issue.
- [x] **2.12 The contact sheet:** slides by targets, grouped by device class, with cached thumbnails, each cell's status, required columns marked, and a locale picker (only `en-US` for now). Selecting a cell opens it on the canvas.
  - Done when an edit to a slide's text updates every cell in its row, and only those thumbnails re-render.
- [x] **2.13 The canvas and the inspector:**
  - On the canvas: drag and rotate the device (the slide's nudge for that class), nudge with the arrow keys (Shift for 10×), and move and resize text frames (the style's layout for the class).
  - In the inspector: one generic row for any `Varying`, with the link badge, the overridden dot, Override for <class> and Revert to Shared. Editing color tokens, fonts, sizes, letter case and tracking.
  - Done when a coordinator test shows a shared edit changes every class and an override changes only its own, and undo reverses a whole drag in one step.
- [ ] **2.14 Remake TrekPoint's screenshots in Stagehand.** Build its style (the brand orange #FFA43C, the dark background and glow, the two-line headline, straight and tilted placements, one running off the edge), add its three slides, drop in the current raw captures, and compare the exports with `src/Exports`.
  - Done when the user agrees they match.
- [ ] **2.15 Remake Flask Master's screenshots** the same way, from a duplicate of TrekPoint's style with Flask Master's colors, fonts and positions. This is the first test of a style built from another.
  - Done when the user agrees they match.

## 3. Capture kit and runner

- [x] **3.1 StagehandScene:** `environmentKey`, `current(key:)`, `decode(_:key:)`, `isCapturing`, and `requestedWindowSize` on macOS.
  - Done when each one has a test.
- [x] **3.2 The capture logic,** as plain functions on `CGImage`s and values, in files that don't import XCTest:
  - blank detection (a uniform color on a downscaled copy)
  - choosing the largest screen that isn't blank (the largest overall when every screen is blank)
  - classifying through StagehandModel
  - the quirks table with `duo-inner-rotated-180`, keyed on the simulator's model and runtime
  - the expectation check (`stagehand.expectation:` failures)
  - `Shot` metadata
  - folder layouts (the default `<locale>/<device class>/<name>.png`, and custom)

  Done when fixture-image tests cover a folded Duo (a black inner display and a cover display), a dark UI that isn't blank, an upside-down inner capture on iOS 27.1, and a newer runtime (the quirk still applies, and is recorded).
- [x] **3.3 The XCUITest side:** `Stagehand.configure`, both `capture(scene:named:...)` overloads, `Readiness`, staging (the configured launch arguments, `-stagehand-capturing`, the scene's environment variable), waiting and settling, the `stagehand.<capture ID>.<name>` and `.meta` attachments, the optional folder output, terminating the app, and the app's window on macOS. Readiness closures are `@MainActor`.
  - Done when the kit builds for iOS, watchOS and macOS, and with Xcode-Beta (CLAUDE.md's Commands).
  - Builds for iOS, watchOS and macOS with Xcode 27.1. The Xcode-Beta build is still to do on a machine that has it.
- [x] **3.4 The fixture app** (`Fixtures/StagehandFixtureApp`): a tiny SwiftUI iOS app with two scenes (one dark, one light) and a screenshot UI test target that uses the kit.
  - Done when its tests pass on an iPhone 17 Pro Max simulator and its result bundle has both captures and their metadata.
- [ ] **3.5 Release the kit as `v0.1.0`,** when the user asks. Other apps add the kit by URL, so the repository has to be on GitHub first (this checkout has no `.git` as of November 2026).
- [x] **3.6 Running tools:** `ProcessRunnerProvider` (the live one uses `Process`, streams output and cancels the whole process group; tests use a fake), and parsing `xcodebuild -list -json` and `xcrun simctl list -j`.
  - Done when the parsers have tests with recorded output.
- [ ] **3.7 The link to an app:** choose an `.xcodeproj` or `.xcworkspace` (kept as a bookmark), its scheme and test target, and a simulator type, runtime and developer directory for each device class. It's saved in `project.json`.
  - Done when a project links to the fixture app and keeps the link after reopening.
  - Built (the Link App sheet and `AppLinkCoordinator`); still to check by hand against the fixture app.
- [x] **3.8 Building and simulators:** `build-for-testing` into Stagehand's derived data folder, finding the `.xctestrun`, creating and booting Stagehand's own simulators ("Stagehand <target>"), and setting their appearance and status bar.
  - Done when tests check the exact command lines, and that only "Stagehand …" simulators are ever booted, changed or erased.
- [x] **3.9 Testing and importing:**
  - `test-without-building` for each simulator and locale, with `-testLanguage`, `-testRegion`, a result bundle, and the `TEST_RUNNER_STAGEHAND_*` variables.
  - `xcresulttool export attachments`, grouping attachments by capture ID, checking sizes against `devices.json`, and writing into `captures/` and `index.json`.
  - Failures from `xcresulttool get test-results tests`.
  - Recovering from "Busy" and "failed preflight checks" by rebooting the simulator and retrying once.
  - Cancel.

  Record the `xcresulttool` output from a real run of the fixture app as test fixtures (open question 5). Done when the import tests pass on those fixtures.
- [x] **3.10 The run UI:** ⌘R runs every capture, cells show progress as each run finishes, Recapture on a cell (`-only-testing:`), and a failed cell opens its result bundle in Xcode.
- [x] **3.11 The end-to-end test:** `EndToEndTests` (with `STAGEHAND_E2E=1`) has the runner build and run the fixture app's tests and import its captures.
  - Done when it passes on the Mac.
- [ ] **3.12 Move TrekPoint onto the kit,** in TrekPoint's repository and under its CLAUDE.md (ask whether the project file change goes straight to the release branch or into a pull request).
  - Add StagehandCapture to `TrekPointScreenshots` only. The app keeps reading its own scene.
  - Replace `ScreenshotTestCase.capture`'s launching, waiting, display choosing and saving, including `appScreenshot()`, with the kit's. Keep `-ui-testing -app-store-preview`, `TREKPOINT_SCREENSHOT_SCENE`, readiness on the render report's `staged: true`, and the 9-second settle.
  - Keep the four folders under `src/Pixelmator Files/AppStoreConnect/Source Images/` with a custom folder layout.
  - Done when the screenshot tests save the same images as before on the iPhone 17 Pro Max, the iPad Pro 13-inch and both Duo displays, and Stagehand imports a run of them.
- [ ] **3.13 Move Flask Master onto the kit.** Its screenshot tests use `ScreenshotTestCase` from MJGameKit's MJScreenshotTesting, whose `capture(scene:named:waitingFor:timeout:settle:)` matches the kit's, so its tests keep their call sites. Either Flask Master's `FlaskMasterScreenshots` target takes StagehandCapture directly, or MJScreenshotTesting is rebuilt on the kit (so every MJGameKit game gets it in a package release). Its folders (`AppStoreScreenshots/iPhone`, `iPad`) stay with a custom layout.
  - Done when its screenshots import into its Stagehand project.

## 4. Sets, variants and every device

- [x] **4.1 The slide pool and sets:**
  - Sets reference slides from the project's pool, each set with its own order (1 to 10 slides).
  - Shared slides show "Also in <set>", with Make Independent Copy.
  - Slides no set uses wait in a Drafts tray.
  - Duplicate Set offers Share Slides or Copy Slides.

  Done when tests show editing a shared slide's text changes it in both sets, and a copy is independent.
- [x] **4.2 Variants:** straight, tilted and zoomed placements in each class's layout, text placements per variant, each slide's variant as a `Varying`, and falling back to straight.
  - Done when a slide can be tilted on iPhone and straight on iPad, and a class with no tilted placement draws it straight.
- [ ] **4.3 iPhone Duo:**
  - Layouts for `duoOuter` and `duoInner` with the fallback chain to `pad`.
  - Duo bezels, or `.none` until there are some.
  - The runner's two passes: the outer display, then the "Unfold the Stagehand iPhone Duo simulator" prompt and the inner display (expecting `duoInner`), asking again when an expectation fails.
  - Done when one run captures TrekPoint on both Duo displays.
  - Built: the fallback chain, `.none` bezels, and the runner's outer-then-inner passes with the unfold prompt (asked again on an expectation failure, tested with a recorded failure). Remaining: a real run on TrekPoint.
- [ ] **4.4 Mac:** the `mac` class with its 16:10 landscape canvas, the app's window captured at the size the runner asks for (`-stagehand-window-size`), a macOS target in the fixture app, and a decision on framed windows or full desktops (open question 7).
  - Done when the fixture app's Mac screenshots export at 2880 × 1800.
  - Built: the fixture app's macOS target and its screenshot tests (which build), per-platform schemes in the app link, the Mac layout in the fixture style (a framed window on the style's background, deciding open question 7 for now), and `EndToEndTests/theRunnerCapturesTheFixtureMacApp()`. Remaining: running that test (`STAGEHAND_E2E_MAC=1`), which drives the real desktop and needs UI automation permission granted once.
- [x] **4.5 Apple Watch:**
  - A watchOS set and the `watch` layout.
  - Check `XCUIScreen` in watchOS UI tests (open question 4), and fall back to the app's screenshot if it doesn't work.
  - A Watch bezel or `.none`, and a watchOS target in the fixture app.
  - Validation that Watch sizes match across localizations.
  - Done when a set shares one slide between iOS and watchOS, and the rest stay separate.
  - `XCUIScreen` works in watchOS UI tests (`EndToEndTests/theRunnerCapturesTheFixtureWatchApp()` captures 422 × 514 on an Ultra 4 simulator), so the kit treats the Watch like iOS.
- [x] **4.6 The issues list:** every flagged cell, plus more than 10 slides in a set, Watch sizes that differ between localizations, a required target with nothing to export, a capture whose size isn't in `devices.json`, a class with no layout, and captures from a runtime newer than a quirk lists (with Undo Quirk).
  - Done when each check has a test.
  - The issues list also shows refused imports.
- [x] **4.7 The search preview:** each set's first three slides as App Store search results show them.
- [ ] **4.8 Decide on appearance** (open question 8): if light and dark should be a capture dimension like locale, add it to the model, the runner (`simctl ui … appearance`) and the contact sheet.

## 5. Library and reuse

- [x] **5.1 Style documents** (`.stagehandstyle`): a style with preview slides and placeholder screens, edited in the same canvas and inspector, and never exported.
  - Done when a style can be designed with no project open.
- [x] **5.2 The library:** `Styles/` and `Bezels/` in Stagehand's iCloud container, a browser for them, and a local folder in Application Support when iCloud isn't available.
  - The Library window lists both, and the New Project window lists the styles.
- [x] **5.3 New Project from a library style,** copying the style in with a `BaseStyle` snapshot.
- [x] **5.4 Save Style to Library,** as a new style or a new version of the one the project came from.
- [x] **5.5 Pulling changes:** "Base updated" on a project whose base has a newer version, a three-way merge over flattened key paths, and a list of conflicts to pick from.
  - Done when tests cover a change only in the library, only in the project, in both, and an override added on one side.
- [x] **5.6 New Project from This:** always the style, optionally the slide skeleton and the text, never the captures or the app link.

## 6. Localization

- [x] **6.1 Locales:** the source, listing and app locale lists, the locale map, and per-locale text in the inspector.
  - The Set inspector edits the lists and the locale map; the Slide inspector edits each locale's text.
- [x] **6.2 The String Catalog round trip:** export and import `.xcstrings` with `<slide slug>.primary` and `.secondary` keys, overrides as Vary by Device variations, and keys of their own for the Duo's classes unless the catalog has a variation for them (open question 6).
  - Done when a test shows text and overrides survive a round trip.
- [x] **6.3 Per-locale auto-fit.**
  - Done when a test shows German text gets its own size without changing English's.
- [x] **6.4 Per-locale captures:** the runner runs each app locale (through the locale map), and a missing capture falls back to the source locale's and is flagged.
  - Done when the fixture app captures in two languages.
  - `EndToEndTests/theRunnerCapturesTwoLanguages()` captures the fixture app in English and German. `-testLanguage` only reaches the test runner, so the kit launches the app with `-AppleLanguages` and `-AppleLocale` too.
- [x] **6.5 Export every listing locale.**

## 7. App Store Connect

Nothing is ever uploaded, deleted or reordered without the user's explicit yes, every time (CLAUDE.md's Rules).

- [x] **7.1 The API key:** the `.p8` key, its key ID and the issuer ID, saved in the Keychain through `KeychainProvider` from Stagehand's settings.
- [x] **7.2 Tokens:** ES256 JWTs with the raw signature, at most 20 minutes long, cached until shortly before they expire.
  - Done when a test verifies a token's signature with the key's public half, and checks its header and claims.
- [x] **7.3 The client,** behind `AppStoreConnectProvider`: finding the app by bundle identifier, its editable version and localizations, and listing, creating, uploading to, committing, deleting and ordering screenshot sets and screenshots.
  - Done when its tests pass against a fake transport.
- [x] **7.4 Upload plans:** for each listing locale and target, what an upload would add, replace, remove and reorder, shown as a dry run, with unchanged images skipped by checksum.
- [ ] **7.5 Uploading** after an explicit confirmation of the plan: reserve, upload each part, commit with the MD5 checksum, wait for processing, then set the order.
  - Done when the user has confirmed and uploaded one real set and App Store Connect shows it as expected.
  - Built (`UploadCoordinator` uploads only after the confirmation dialog). Not run against App Store Connect: that's for the user to confirm and try.
- [x] **7.6 Custom product pages:** a set can target a custom product page's screenshot sets.
  - A set's Uploads To field takes the page's ID; its uploads plan against that page's editable version.

## 8. iPad

- [ ] **8.1 Run Stagehand on an iPad,** once there is one: touch editing on the canvas (drag, rotate, pinch), pointer hover effects, and keyboard shortcuts with a keyboard.
- [ ] **8.2 Projects and the library through Files:** open projects and styles from iCloud Drive, fonts and bezels from the library, and the capture UI hidden.
  - Done when a project's exports from the iPad match the Mac's.

## 9. Templates, devices and bezels

PLAN.md's Launching and new projects, Templates, Devices, and Bezels from Apple Design Resources sections. The project's format goes to 3 (and the style file's with it), migrating format 2 on open.

- [x] **9.1 The Welcome window and the style document type.** Declare `com.mazjap.stagehand.style` in `CFBundleDocumentTypes`, and show a Welcome window at launch (New Project, Open…, New Template Set, recent documents) instead of the bare open panel.
  - Done when a test checks that every `DocumentGroup` type is declared, and the app opens to the Welcome window.
  - `DocumentTypeTests` fails with the old `Info.plist` and passes with the fix. Opening to the Welcome window is still to check by hand (this machine can't see the screen).
- [x] **9.2 Templates in the model (format 3):** `Template`, `TemplateLayout`, `TemplateElement` and extra elements, `Slide.template`, `Slide.detachments` and extra content, the resolver and renderer drawing extra text, device and image elements, and the migration from layouts, variants and nudges (copying borrowed layouts into the classes a project uses).
  - Done when format 2 fixtures migrate and render the same, and tests cover a template per device, hidden standard elements, extra elements, and a detachment.
  - All 17 of the format 2 fixture's cells draw where format 2's resolver drew them (recorded from the old code).
- [x] **9.3 Devices and lineups:** `Project.devices`, `targets`, `slideOrder`, `productPages`, `Slide.excludedDevices`, lineups computed in place of sets, per-device numbering in exports, per-device validation, and the migration from sets.
  - Done when a test migrates an iOS set and a watchOS set sharing a slide into one order with the right devices off, and a slide that's off for a device isn't exported for it.
- [x] **9.4 The template editor and locked slides:** a Templates section in the sidebar, the canvas editing a template's layout per class, a slide's moves asking to detach (Edit Template Instead, Detach This Slide, Cancel), detachment badges and Reset to Template, adding a class's layout from another class or blank, adding and removing extra elements, and dragging a template onto the slide list to make a slide.
  - Done when coordinator tests show a template edit moves every slide using it, a slide's move is refused until it's detached, and a detached slide stops following the template only for that element and class.
- [x] **9.5 New Project flow:** devices first, then a built-in starter, a library template set, or Start from Scratch; Add Device… later, asking about existing slides; turning a slide off and on for a device.
  - Done when a project can start with iPhone alone and add iPad later, and a test shows adding a device can leave existing slides off it.
  - A project with no slides opens on its first template. New projects pin their templates' bezels.
- [x] **9.6 Bezels from Apple Design Resources:** `BezelSource` (the page's links and their headers), the license agreement shown before mounting, `BezelDownloader` (download, mount, import every PNG, detach), never overwriting an imported bezel, pinning new template layouts, "Newer bezel available" with Update Bezel…, embedding pinned bezels in projects, and the Library window's bezel list.
  - Done when tests cover parsing a recorded page, the downloader's commands (fake process runner), newer-bezel detection, and a project that opens with its embedded bezel when the library has none. Then download real bezels once and record what the images contain (open question 11).
  - Built, with those tests. The iPhone 18 disk image was installed for real (the user agreed to its license) and its names parse as expected: eight portrait bezels, each screen detected at its App Store size. It showed two bugs, both fixed with regression tests: the Finder background in `.DropDMGBackground/` was in the PNG search, and the 6.9-inch target drew in the iPhone 18 Pro rather than the Pro Max. The iPad Pro (M5), Apple Watch Ultra 4 and iPhone Duo images were installed too (open question 11), and the library keeps one bezel per device class, each its class's default.
- [x] **9.7 Keep App Store Connect's order:** an upload option that adds and replaces screenshots without reordering them.
  - Done when an upload plan test shows no reorder with the option on.
- [x] **9.8 Every layer of Apple's bezels:** not needed. Apple's PNGs already draw the whole device (frame, side buttons, and the Dynamic Island over the screen, which `SceneView` draws above the capture), and the Photoshop files have no separate layers for them (open question 11).

## 10. Linking an app

- [ ] **10.1 Pick a scheme, and let it decide the test target:** the link sheet asks for a scheme and a test target, which look like the same choice, and a full run ignores the test target (only Recapture uses it). TrekPoint was linked to the `TrekPoint` scheme with `TrekPointScreenshots` as its target, so a run ran the app's unit and UI tests instead of its screenshots. Read the chosen scheme's test targets (its test action, or its test plan), fill in the test target from them, and only ask when there's more than one. Full runs pass `-only-testing:<test target>`, and a saved link whose scheme doesn't include its target gets a clear warning rather than running the wrong tests. Update `README.md` and `skills/stagehand/SKILL.md`.
  - Also fixes picking the `.xctestrun`: derived data is shared per project, and the runner takes the name that sorts last, so after switching from `TrekPoint` to `TrekPointScreenshots` it would still pick the old `TrekPoint_…` file. Pick the current scheme's file instead.
  - Done when tests show a scheme with one test target needs no choice, a scheme with several asks, a full run's command line has `-only-testing:`, a mismatched link warns, and a scheme change uses the new scheme's `.xctestrun` with the old one still on disk.

## Every September

When new devices and an Xcode release arrive:

- [ ] Check `devices.json` against Apple's Screenshot specifications page.
- [ ] Check each quirk against the new simulator runtimes.
- [ ] Refresh the `xcresulttool` fixtures with the new Xcode.
- [ ] Re-export the Xcode skills.
- [ ] Check whether `simctl` or XCTest can fold the iPhone Duo yet (open question 3). If one can, replace the runner's manual unfold step.
