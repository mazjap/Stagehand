---
name: stagehand
description: How to use Stagehand, the App Store screenshot app, and its capture kit (the Swift package products StagehandCapture, StagehandScene and StagehandModel from github.com/mazjap/Stagehand). Use when adding or changing an app's App Store screenshot UI tests for Stagehand; when moving screenshot tests from another helper (like MJScreenshotTesting's ScreenshotTestCase or an app's own) onto the kit; when code imports StagehandCapture or StagehandScene; when staging screenshot scenes in an app; or when helping someone link an app to Stagehand, run captures, match screenshots to slides, or troubleshoot a capture run.
---

# Stagehand

Stagehand is a macOS (and iPadOS) app that makes App Store screenshots from **templates** and **slides**, and fills each slide with a **capture**: a raw screenshot of the app. Captures come from the app's own screenshot UI tests, which use Stagehand's **capture kit**. Stagehand's runner builds those tests, runs them on its own simulators, and imports the screenshots.

This skill covers the kit (for the app's screenshot tests and the app itself) and the parts of the app an agent needs to set up and check a capture run. The repository's README has the full app guide.

## The kit

The root of `https://github.com/mazjap/Stagehand` is a Swift package with no dependencies, for iOS 17, macOS 14 and watchOS 10:

| Product | Link it to | Purpose |
| --- | --- | --- |
| `StagehandCapture` | the **screenshot UI test target only** | `Stagehand.configure` and `XCTestCase.capture(scene:named:…)` |
| `StagehandScene` | the **app target**, optional | reading the staged scene (`StagehandScene.decode`, `.current()`) |
| `StagehandModel` | nothing directly | device classes and screenshot sizes, pulled in by the others |

Add it by URL in Xcode (File › Add Package Dependencies…), pinned to a version tag once one is released (before that, the `main` branch). It changes the app's Xcode project and `Package.resolved`, so follow the app repository's rules for where that goes (a branch, a pull request), and ask if they don't say.

Keep screenshot tests in their own UI test target and scheme. The scheme Stagehand is linked to must include that target in its test action.

### Configuring

Once per test class, from `class func setUp()` (the configuration is a lock-protected global):

```swift
import StagehandCapture
import XCTest

final class AppStoreScreenshots: XCTestCase {
    override class func setUp() {
        super.setUp()
        
        Stagehand.configure { config in
            config.launchArguments = ["-ui-testing", "-app-store-preview"]  // the app's own flags
            config.launchEnvironment = [:]
            config.sceneEnvironmentKey = "MYAPP_SCREENSHOT_SCENE"             // default: "STAGEHAND_SCENE"
            // Optional: also save to <repository>/AppStoreScreenshots/<iPhone or iPad>/<name>.png.
            // Without a layout, it's <locale>/<device class>/<name>.png.
            let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            config.folder = FolderOutput(root: root.appending(path: "AppStoreScreenshots"), layout: .custom { path in
                "\(path.deviceClass == .pad ? "iPad" : "iPhone")/\(path.name).png"
            })
            // timeout (10), settle (3), settleAfterReadiness (1), macWindowSize (1440 × 900)
        }
    }
}
```

`config.folder` also writes each PNG into a folder when the process can write there (the simulator, or a Mac). Stagehand's runs turn it off (`STAGEHAND_FOLDER_OUTPUT=off`), so a run never overwrites the folder. Keep that folder outside the test target's own folder (a folder-synchronized group would bundle old images into the tests) and gitignore it.

### Capturing

```swift
@MainActor
func test01Level() throws {
    try capture(scene: "level", named: "01-level", waitingFor: { $0.buttons["Pause"] })
}

@MainActor
func test03Map() throws {
    try capture(
        scene: MapScene(camera: .frame),                                  // any Encodable: sent as sorted-key JSON
        named: "read-the-land",
        until: .value(of: { $0.otherElements["map-render-report"] }, contains: "staged: true"),
        timeout: 60,
        settle: 9
    )
}
```

`capture(scene:named:waitingFor:until:timeout:settle:)`, an `XCTestCase` extension, `@MainActor`, `throws`:

1. Launches a fresh `XCUIApplication` with `launchArguments` + `-stagehand-capturing` (+ `-AppleLanguages`/`-AppleLocale` during a Stagehand run), `launchEnvironment`, and the scene under `sceneEnvironmentKey`.
2. Waits for readiness, if given: `waitingFor:` is shorthand for `until: .element(…)`. `Readiness` is `.element { app in … }` (exists), `.value(of: { app in … }, contains: "…")` (value or label contains the text), or `.condition { app in … }` (polled every quarter second). Not ready by `timeout` fails the test.
3. Settles (`settle`, or 3 seconds, or 1 second after readiness), then screenshots every `XCUIScreen` (the app's first window on macOS), keeps the largest one that isn't blank, and applies known simulator fixes (the iPhone Duo's inner display is upside down in iOS 27.1). A screenshot within 2 pixels of a size in `devices.json`, in width and in height, counts as that size (the Duo's iOS 27.2 simulator takes its inner display at 2006 × 2852), and Stagehand scales it to fill the bezel's screen.
4. Attaches `stagehand.<capture ID>.<name>` (the PNG) and `stagehand.<capture ID>.meta` (JSON metadata: name, scene, device class and size target from the pixel size, locale, run ID, simulator, fixes applied), and writes the folder copy if configured.
5. Fails the test if a Stagehand run expected another device class (`STAGEHAND_EXPECTED_CLASS`).
6. Terminates the app.

**`named` is the capture key.** A Stagehand slide shows the capture whose key matches its own capture key (per device class and locale). Use lowercase letters, numbers and dashes. Never a dot: Xcode inserts its export suffix before an attachment name's last dot.

### In the app

The app stages the scene only in debug builds:

```swift
#if DEBUG
import StagehandScene

let scene = StagehandScene.decode(MapScene.self, key: "MYAPP_SCREENSHOT_SCENE")   // or .current(key:) for a String
#endif
```

An app that already reads its own scene variable doesn't need `StagehandScene`: set `config.sceneEnvironmentKey` to that variable and keep the app as it is. A Mac app should size its window to `StagehandScene.requestedWindowSize` (sent as `-stagehand-window-size <w>x<h>`). `StagehandScene.isCapturing` checks for `-stagehand-capturing`.

### Moving existing screenshot tests onto the kit

- **MJScreenshotTesting's `ScreenshotTestCase`** (MJGameKit): same `capture(scene:named:waitingFor:timeout:settle:)` shape, so call sites stay. Change the class to subclass `XCTestCase`, move the `sceneEnvironmentKey` override and `ScreenshotLaunch.arguments` (`-ui-testing -app-store-preview`) into `Stagehand.configure`, and replace `screenshotsFolder` with `config.folder` and a `.custom` layout giving `iPhone/` and `iPad/` folders. Link `StagehandCapture` instead of `MJScreenshotTesting` in the screenshot target.
- **An app's own helper:** keep what's specific to the app before `capture` (setting `XCUIDevice.shared.location` or orientation, `app.resetAuthorizationStatus(for:)`), and replace its launching, waiting, display choosing (including any iPhone Duo or blank-screen handling) and saving with `capture`. A long wait for content (map tiles, imagery) is `until:` plus `settle:`.
- **Per-capture launch arguments** aren't a `capture` parameter. Call `Stagehand.configure` before that capture to change `launchArguments` or `launchEnvironment`, and set them back after.
- Rename tests' capture names to keys (`"1. Terrain Made Clear"` → `"terrain-made-clear"`), or set each slide's capture key in Stagehand to match.

### Checking a test target

```sh
xcodebuild test -project MyApp.xcodeproj -scheme MyAppScreenshots -parallel-testing-enabled NO \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -resultBundlePath /tmp/shots.xcresult
xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path /tmp/shots
```

`/tmp/shots/manifest.json` should list a `stagehand.<UUID>.<name>` image and a `stagehand.<UUID>.meta` file per test (Xcode inserts `_<n>_<UUID>` before the last dot when exporting). Never boot, erase or change the user's own simulators: create one for the check, or use one the user names.

### Environment the runner sends

`xcodebuild` strips a `TEST_RUNNER_` prefix and passes the rest to the test runner only (not to the app; the kit relays the language). Anything else set on `xcodebuild` doesn't reach the tests.

| Variable | Meaning |
| --- | --- |
| `STAGEHAND_LOCALE` | the project locale this pass captures (recorded in the metadata) |
| `STAGEHAND_APP_LANGUAGE`, `STAGEHAND_APP_REGION` | what the kit launches the app in (`-AppleLanguages`, `-AppleLocale`) |
| `STAGEHAND_EXPECTED_CLASS` | the device class the pass expects; another size fails the test |
| `STAGEHAND_RUN_ID` | ties the captures to the run |
| `STAGEHAND_FOLDER_OUTPUT` | `off` during runs, so `config.folder` isn't written |

## The app, for an agent setting up captures

- **Link App** (Capture menu): the `.xcodeproj` or `.xcworkspace`, the **scheme** (its test action must include the screenshot target, which is often a scheme of its own), the **test target**, and a simulator type and runtime per device class. Pick the simulator by the screenshot size the project exports: a Pro Max for the 6.9" iPhone (1320 × 2868), a 13" iPad Pro (2064 × 2752), an Ultra for the largest watch (422 × 514).
- **Run Captures** (⌘R) runs `build-for-testing` once per developer directory and platform, then `test-without-building -parallel-testing-enabled NO` per device class and locale, on simulators named "Stagehand <target>" that Stagehand creates. The iPhone Duo's outer display runs before the inner one, with a prompt to unfold it in Device Hub. Results import with `xcresulttool`; a failed cell opens its result bundle.
- **Matching:** a capture is stored by (capture key, device class, locale). The device class comes from pixel size alone (`devices.json`), never the simulator's name. Each slide's capture key is in the Slide inspector, with a menu of every key there are captures for.
- **Without the kit**, image attachments that aren't tied to a failure import too, keyed by the attachment's name slugged (`01-level`, `1-terrain-made-clear`), without the Duo handling, languages or size check.
- **Other ways in:** drop images on a slide's cell or the canvas, or Capture › Import Screenshots Folder… (keys from file names).
- **A build that fails** on a package macro or plugin that "must be enabled before it can be used" needs the user to build the app once in Xcode and choose Trust & Enable. Stagehand doesn't skip that check.

## The documents, if you have to read one

A project is a `.stagehand` package: `project.json` (format 3: the template set with its templates, devices, slides keyed by UUID, the slide order, product pages, and the app link), `captures/` (`index.json` and the PNGs), `fonts/`, `assets/`, and `bezels/` (the bezels the project uses). A template set is a `.stagehandstyle` package with `style.json`. Prefer changing them through the app, which migrates older formats and registers undo; never rename a key, and never commit Apple's bezel images anywhere.
