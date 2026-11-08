# Stagehand

Stagehand makes App Store screenshots. You design a few **templates** (where the headline, the subline and the device go), make **slides** from them, and Stagehand renders every size App Store Connect asks for, in every language, with Apple's real device bezels. It can also run your app's screenshot UI tests on its own simulators and drop the results onto the right slides, and upload the finished screenshots to App Store Connect.

The repository has two parts:

- **The Stagehand app** (`App/`), for macOS 27 and iPadOS 27.
- **The capture kit** (the root `Package.swift`), a small Swift package your app's screenshot UI test target uses, so Stagehand knows which screenshot is which. It supports iOS 17, macOS 14 and watchOS 10, and has no dependencies.

Stagehand is young (the kit is 0.x), and was built for the author's own apps first. Expect rough edges, and changes to the kit before 1.0.

> **For coding agents:** [`skills/stagehand/SKILL.md`](skills/stagehand/SKILL.md) is a skill that explains the kit and the app to an agent. Copy (or link) the `skills/stagehand` folder into your project's `.claude/skills/`.

## Contents

- [Requirements](#requirements)
- [Building the app](#building-the-app)
- [Using the app](#using-the-app)
- [The capture kit](#the-capture-kit)
- [Repository layout](#repository-layout)
- [Development](#development)
- [License](#license)

## Requirements

- **The app:** macOS 27 (or iPadOS 27) and Xcode 27. Capturing (running your screenshot tests) is Mac only.
- **The kit:** any app whose screenshot tests run on iOS 17, macOS 14 or watchOS 10 or later.
- **iPhone Duo captures:** an iOS 27.1 or newer simulator that supports the Duo.

## Building the app

1. Open `App/Stagehand.xcodeproj` and choose the **Stagehand** scheme.
2. In the Stagehand target's **Signing & Capabilities**, choose your own team, and change the bundle identifier (`com.mazjap.Stagehand`) to one of yours.
3. The app keeps its library (template sets and bezels) in iCloud Drive, in the container `iCloud.com.mazjap.Stagehand`. Either change it to a container of your own (in the target's iCloud capability and in `LiveUbiquity.containerIdentifier`), or remove the iCloud capability. Without iCloud, the library lives in `~/Library/Application Support/Stagehand/Library`.
4. Build and run. The App Sandbox is off, because Stagehand runs `xcodebuild` and reads your app's project wherever it is.

The core tests need none of this (see [Development](#development)).

## Using the app

### Projects and template sets

A **project** (`.stagehand`) holds one app's screenshots: its devices, slides, captures, fonts and bezels. A **template set** (`.stagehandstyle`) is a reusable look: colors, fonts, text styles and templates. Every project has its own copy of a template set, which you can save to the library and reuse.

Stagehand opens to a **Welcome** window with **Open…**, **New Project** (and **New Template Set** in its menu), and your recent documents. **New Project** asks for:

- **Devices:** iPhone, iPad, iPhone Duo (outer and inner displays), Apple Watch, Mac. Start with one; add more later in the **Project** inspector.
- **A template set:** a built-in starter, one from your library, or **Start from Scratch**.

### Templates and slides

A **template** places three standard elements, **Primary Text**, **Secondary Text** and the **Main Device** (a bezel showing a screenshot), plus any extra text, device or image elements, with its own layout for each device. Templates are listed at the top of the sidebar; click one to edit it on the canvas.

- **Moving something in a template moves it on every slide that uses the template.**
- A template shows its own **placeholder text** (set in the **Template** inspector), never a slide's. New slides start with it.
- **Drag a template** onto the slide list or the contact sheet to make a slide. A slide can use one template on iPhone and another on iPad.
- On a slide, elements are **locked** to the template. Moving one asks first: **Edit Template Instead**, **Detach This Slide** (only this slide moves, and stops following the template for that element), or **Cancel**. **Reset to Template** undoes a detach.
- Each slide can be turned off for any device, and every device shows the slides in the same order. A slide that's off for the device on the canvas says so, with a button to turn it on. **Custom product pages** (in the sidebar's **Lineups**) reuse slides from the same pool.

### Text

Fonts, sizes, colors, letter case, tracking and line spacing belong to the template set (the **Template Set** inspector), so every template shares them. Sizes are in **points on the screenshot** (a point is a pixel of the exported image, as in design apps), and every slider has a field to type a number. Fonts you choose are embedded in the project.

Text is always drawn at its size, on every slide and in the template editor, and **wraps** to as many lines as it needs at its box's width: a text box only has a width, and grows (away from its anchor point) to fit its lines. A single word wider than its box breaks across lines, so keep sizes and box widths in proportion to your longest words.

### Bezels

Stagehand uses Apple's own product bezels from [Apple Design Resources](https://developer.apple.com/design/resources/). They're Apple's files, so they're never in this repository: download them in **Window › Library** (⇧⌘L). Each download shows **Apple's license agreement**, which you have to agree to before Stagehand opens it.

- A device class with one bezel uses it; otherwise **Library Default** picks the one whose screen matches the screenshot's size.
- A template keeps the bezel it was made with. When a newer one is downloaded, the template says so, and **Update Bezel…** shows what would change before switching.
- Projects embed the bezels they use, so they open correctly anywhere.
- Until a device has a bezel, it's drawn as a plain frame.

### Screenshots (captures)

Each slide has a **capture key** per device (in the **Slide** inspector). A screenshot is stored by its capture key, device and language, and a slide shows the one that matches. The menu next to the capture key lists every screenshot there is for that device. You can get screenshots in three ways:

1. **Drag and drop:** onto a slide's cell in the contact sheet, or onto the canvas, for that slide. Dropped on the contact sheet's background, a file goes to the slide whose capture key matches its name (`Read the Land.png` is `read-the-land`). The device always comes from the pixel size.
2. **Capture › Import Screenshots Folder…:** imports every image in a folder and its subfolders, keyed by file name, for screenshot tests you run yourself.
3. **Capture › Run Captures (⌘R):** runs your app's screenshot tests. First, **Capture › Link App…**: choose the `.xcodeproj` or `.xcworkspace` (or its folder), the **scheme** (its test action has to include the screenshot test target), the **test target**, and a simulator for each device. Stagehand builds once, then runs the tests on its own simulators (named "Stagehand …"; yours are never touched), once per device and language, and imports the results. **Recapture** on a cell re-runs just that test.

   Run Captures works best with [the capture kit](#the-capture-kit). Tests that attach plain screenshots (`XCTAttachment(screenshot:)` with a name) also import, keyed by the attachment's name.

   If the build fails with a macro that "must be enabled before it can be used", open your app in Xcode and build it once, choosing **Trust & Enable**.

### The canvas

- Drag elements to move them, and their handles to resize; pinch and rotate on a trackpad; arrow keys nudge (Shift for 10×). Drags snap to edges and centers; hold ⌘ to move freely.
- Scroll to pan, ⌘-scroll to zoom, ⌘+ / ⌘− / ⌘0 to zoom in, out and to fit. Zoom out to drag things past the edge of the screenshot.
- **View › Preview** (⌥⌘P, or the eye button) hides outlines, handles and guides, so you see the slide as it exports. Esc leaves it.

### Languages

Set the source language and the listing languages in the **Project** inspector. Text can be overridden per language and per device. **Strings › Export…** and **Import…** write and read a String Catalog (`.xcstrings`) for translating.

### Export and upload

- **File › Export Screenshots… (⌘E)** writes `<language>/<size>/<number>-<slide>.png` for every size you've chosen in the **Project** inspector, with no alpha channel, as App Store Connect requires.
- **File › Upload to App Store Connect…** shows what an upload would change first, and uploads only after you confirm. It keeps screenshots that haven't changed, and can keep the order you set in App Store Connect. Add your App Store Connect API key (the `.p8` file, its key ID and the issuer ID) in **Settings**; it's stored in the Keychain.

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New Project / New Template Set | ⌘N / ⌥⌘N |
| Export Screenshots | ⌘E |
| New Slide / Duplicate Slide | ⇧⌘N / ⌘D |
| Contact Sheet / Canvas | ⌘1 / ⌘2 |
| New Template / Edit Slide's Template / Back to Slide | ⌥⇧⌘N / ⌥⌘T / ⌘⎋ |
| Run Captures / Stop Run | ⌘R / ⌘. |
| Zoom In / Zoom Out / Zoom to Fit / Preview | ⌘+ / ⌘− / ⌘0 / ⌥⌘P |
| Issues / Search Preview | ⇧⌘I / ⇧⌘P |
| Library / Welcome to Stagehand | ⇧⌘L / ⇧⌘1 |

## The capture kit

The kit has three products:

| Product | Add it to | What it does |
| --- | --- | --- |
| `StagehandCapture` | your **screenshot UI test target** | Launches your app into a scene, waits for it, captures the screen, and attaches it with metadata Stagehand reads. |
| `StagehandScene` | your **app target** (optional) | Reads the scene the test is staging. Keep its use behind `#if DEBUG`. |
| `StagehandModel` | (comes with the others) | Device classes and screenshot sizes (`devices.json`), shared with the app. |

### Adding it

In Xcode, **File › Add Package Dependencies…**, enter `https://github.com/mazjap/Stagehand`, and add `StagehandCapture` to your screenshot UI test target only (and `StagehandScene` to your app, if you want it). Pin a version tag once one is released; until then, use the `main` branch.

Keep screenshot tests in a test target and scheme of their own, so they never run with your other UI tests.

### Writing screenshot tests

```swift
import StagehandCapture
import XCTest

final class AppStoreScreenshots: XCTestCase {
    override class func setUp() {
        super.setUp()
        
        Stagehand.configure { config in
            config.launchArguments = ["-ui-testing"]          // your app's own
            config.sceneEnvironmentKey = "MYAPP_SCREENSHOT_SCENE" // or the default, STAGEHAND_SCENE
        }
    }
    
    @MainActor
    func test01Home() throws {
        // Waits for the element, settles, then captures. The name is the capture key.
        try capture(scene: "home", named: "home", waitingFor: { $0.buttons["Play"] })
    }
    
    @MainActor
    func test02Map() throws {
        // Any Encodable scene is sent as JSON.
        try capture(
            scene: MapScene(latitude: 37.74, longitude: -119.57),
            named: "map",
            until: .value(of: { $0.otherElements["map-status"] }, contains: "ready"),
            settle: 3
        )
    }
}
```

`capture(scene:named:waitingFor:until:timeout:settle:)`:

- **`scene`:** a `String`, or any `Encodable` value (sent as JSON), put in the app's launch environment under `sceneEnvironmentKey`.
- **`named`:** the capture key, which a slide's capture key matches. Use letters, numbers and dashes (no dots).
- **`waitingFor`** / **`until`:** what to wait for before settling. `until` takes a `Readiness`: `.element { … }` (exists), `.value(of: { … }, contains: "…")` (its value or label contains the text), or `.condition { app in … }` (polled until true).
- **`timeout`** and **`settle`:** how long to wait for readiness (10 seconds), and how long to settle before capturing (3 seconds, or 1 second after readiness).

It captures every display and keeps the largest one that isn't blank (which is how the iPhone Duo's open inner display is captured), fixes known simulator bugs (the Duo's inner display comes back upside down on iOS 27.1), and fails the test if the screenshot isn't the size a Stagehand run expected. A screenshot within 2 pixels of a size, in width and in height, counts as that size, since simulators can be a pixel off (the Duo's iOS 27.2 simulator takes its inner display at 2006 × 2852). Stagehand scales a capture to fill the bezel's screen, cropping anything that doesn't fit, and exports are always the exact size App Store Connect asks for.

### Configuration

Set these in `Stagehand.configure { … }`, usually from `class func setUp()`:

| Setting | Default | |
| --- | --- | --- |
| `launchArguments` | `[]` | Every capture launches with these (the kit adds `-stagehand-capturing`, and the language during a Stagehand run). |
| `launchEnvironment` | `[:]` | Environment variables for every launch. |
| `sceneEnvironmentKey` | `STAGEHAND_SCENE` | Where the scene goes. |
| `folder` | `nil` | `FolderOutput(root:layout:)`: also saves each screenshot into a folder (`<locale>/<device class>/<name>.png`, or a `.custom { path in … }` layout). Skipped during Stagehand runs. |
| `macWindowSize` | 1440 × 900 | The window size Mac captures ask for. |
| `timeout`, `settle`, `settleAfterReadiness` | 10, 3, 1 seconds | |

### In your app

Your app reads the scene and stages it (sample data, a fixed date, a screen opened), only in debug builds:

```swift
#if DEBUG
import StagehandScene

if let scene = StagehandScene.decode(MapScene.self) {   // or StagehandScene.current() for a String
    stage(scene)
}
#endif
```

`StagehandScene.isCapturing` says whether the kit launched the app. A Mac app should size its window to `StagehandScene.requestedWindowSize`, so every capture is the same size.

### Languages

During a Stagehand run, the kit launches your app with `-AppleLanguages` and `-AppleLocale` for each of the project's languages, so screenshots come out in every language without code of your own. (`-testLanguage` alone only reaches the test runner, not your app.)

### Without the kit

Tests that attach plain screenshots also work with **Run Captures**: each image attachment (not one from a failure) becomes a capture keyed by its name, and its device comes from its size. You lose what the kit adds: the iPhone Duo's displays, launching in each language, and the size check.

## Repository layout

| Path | |
| --- | --- |
| `Package.swift`, `Sources/`, `Tests/` | The capture kit and its tests. |
| `App/Stagehand.xcodeproj`, `App/Stagehand/` | The app. |
| `App/Packages/StagehandCore/` | Most of the app's code: the model, documents, the resolver and renderer, bezels, the capture runner, and the App Store Connect client. |
| `Fixtures/StagehandFixtureApp/` | A tiny app with screenshot tests that use the kit, for the runner's end-to-end tests. |
| `skills/stagehand/` | The skill for coding agents. |
| `CLAUDE.md`, `PLAN.md`, `TASKS.md` | How the project is built and run, the design, and the work list. |

## Development

```sh
# The kit's tests
swift test

# The app's core tests (no signing or simulators needed)
swift test --package-path App/Packages/StagehandCore

# The app, and its tests (needs your signing team; see Building the app)
xcodebuild test -project App/Stagehand.xcodeproj -scheme Stagehand -destination 'platform=macOS'

# End to end: the runner builds and drives the fixture app's screenshot tests on a simulator (slow, opt-in)
STAGEHAND_E2E=1 swift test --package-path App/Packages/StagehandCore --filter EndToEndTests
```

The renderer's snapshot tests run on macOS 27 and are skipped elsewhere. `CLAUDE.md` has the architecture, conventions and gotchas, and is the place to start before changing anything.

## License

Stagehand is available under the [MIT License](LICENSE). Apple's product bezels aren't part of it: they're downloaded from Apple Design Resources under Apple's own license, which you agree to in the app, and they're never in this repository.
