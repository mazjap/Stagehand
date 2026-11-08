#if os(macOS)
import Dependencies
import Foundation
import Observation
import StagehandModel
import UniformTypeIdentifiers

/// The Link App sheet's coordinator: choosing an Xcode project, its scheme and test target, and each class's simulator.
@Observable
@MainActor
public final class AppLinkCoordinator {
    public enum Intent {
        case load
        case chooseProject(URL)
        case setScheme(String)
        case setTestTarget(String)
        case setSimulator(DeviceClass, SimulatorSpec?)
        case setOverridesStatusBar(Bool)
        case setPlatformScheme(RunPlan.Platform, String)
        case setPlatformTestTarget(RunPlan.Platform, String)
        case save
    }
    
    public private(set) var projectURL: URL?
    public private(set) var schemes: [String] = []
    public private(set) var targets: [String] = []
    public private(set) var deviceTypes: [SimctlList.DeviceType] = []
    public private(set) var runtimes: [SimctlList.Runtime] = []
    public private(set) var isLoading = false
    public private(set) var draft: AppLink?
    public var errorMessage: String?
    
    /// The device classes the project's sets use.
    public let deviceClasses: [DeviceClass]
    
    private let project: ProjectCoordinator
    @ObservationIgnored @Dependency(\.captureRunner) private var runner
    @ObservationIgnored @Dependency(\.fileManager) private var fileManager
    
    public init(project: ProjectCoordinator) {
        self.project = project
        self.draft = project.project.appLink
        self.deviceClasses = DeviceClass.allCases.filter { project.project.devices.contains($0) && $0 != .mac }

        if let link = draft {
            var stale = false
            projectURL = (try? URL(resolvingBookmarkData: link.project, options: [.withoutUI], bookmarkDataIsStale: &stale)) ?? URL(filePath: link.projectPath)
        }
    }
    
    // MARK: - Choosing a Project
    
    /// What Choose… accepts: Xcode projects, workspaces, and the folder holding one.
    ///
    /// `UTType(filenameExtension:)` alone assumes the file is data, so for `xcodeproj` it makes up a dynamic type
    /// that no project (a package) conforms to, and the open panel greyed every project out.
    public static let projectTypes: [UTType] = [
        UTType(filenameExtension: "xcodeproj", conformingTo: .package) ?? .package,
        UTType(filenameExtension: "xcworkspace", conformingTo: .package) ?? .package,
        .folder,
    ]
    
    /// The Xcode project a chosen URL means: itself when it's a project or workspace, or else the one in the folder,
    /// a workspace before a project (since a workspace includes its projects' packages).
    public static func xcodeProject(for url: URL, fileManager: any FileManagerProvider) -> URL? {
        if isXcodeProject(url) {
            return url
        }
        
        let contents = ((try? fileManager.contentsOfDirectory(at: url)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        return contents.first { $0.pathExtension == "xcworkspace" } ?? contents.first { $0.pathExtension == "xcodeproj" }
    }
    
    private static func isXcodeProject(_ url: URL) -> Bool {
        ["xcodeproj", "xcworkspace"].contains(url.pathExtension)
    }
    
    // MARK: - Computed Properties
    
    /// Platforms other than iOS that the project's devices capture, which can have schemes of their own.
    public var otherPlatforms: [RunPlan.Platform] {
        let platforms = Set(project.project.devices.map(RunPlan.Platform.init))
        return [.watchOSSimulator, .macOS].filter(platforms.contains)
    }
    
    public var canSave: Bool {
        guard let draft else { return false }
        return !draft.scheme.isEmpty && !draft.testTarget.isEmpty
    }
    
    /// Device types suited to a class, by product family.
    public func deviceTypes(for device: DeviceClass) -> [SimctlList.DeviceType] {
        let family = switch device {
        case .phone, .duoOuter, .duoInner: "iPhone"
        case .pad: "iPad"
        case .watch: "Apple Watch"
        case .mac: "Mac"
        }
        
        return deviceTypes.filter { $0.productFamily == family }
    }
    
    public func runtimes(for deviceType: String) -> [SimctlList.Runtime] {
        SimctlList(devicetypes: deviceTypes, runtimes: runtimes, devices: nil).runtimes(supporting: deviceType)
    }
    
    // MARK: - Intents
    
    public func handle(_ intent: Intent) {
        switch intent {
        case .load:
            loadSimulators()
            
            if let projectURL {
                loadSchemes(projectURL)
            }
        case let .chooseProject(chosen):
            guard let url = Self.xcodeProject(for: chosen, fileManager: fileManager) else {
                errorMessage = "\(chosen.lastPathComponent) has no Xcode project or workspace in it."
                return
            }
            
            errorMessage = nil
            projectURL = url
            let bookmark = (try? url.bookmarkData()) ?? Data()
            draft = AppLink(
                project: bookmark,
                projectPath: url.path(percentEncoded: false),
                scheme: draft?.scheme ?? "",
                testTarget: draft?.testTarget ?? "",
                simulators: draft?.simulators ?? [:],
                overridesStatusBar: draft?.overridesStatusBar ?? true
            )
            loadSchemes(url)
        case let .setScheme(scheme):
            draft?.scheme = scheme
        case let .setTestTarget(target):
            draft?.testTarget = target
        case let .setSimulator(device, spec):
            draft?.simulators[device] = spec
        case let .setOverridesStatusBar(value):
            draft?.overridesStatusBar = value
        case let .setPlatformScheme(platform, scheme):
            draft?.platformSchemes = (draft?.platformSchemes ?? [:]).merging([platform.rawValue: scheme]) { $1 }.filter { !$0.value.isEmpty }
        case let .setPlatformTestTarget(platform, target):
            draft?.platformTestTargets = (draft?.platformTestTargets ?? [:]).merging([platform.rawValue: target]) { $1 }.filter { !$0.value.isEmpty }
        case .save:
            project.handle(.setAppLink(draft))
        }
    }
    
    private func loadSchemes(_ url: URL) {
        let runner = runner
        isLoading = true
        
        Task { [weak self] in
            do {
                let list = try await runner.list(projectURL: url)
                self?.schemes = list.schemes
                self?.targets = list.targets
                
                if self?.draft?.scheme.isEmpty == true, let scheme = list.schemes.first(where: { $0.localizedCaseInsensitiveContains("screenshot") }) {
                    self?.draft?.scheme = scheme
                }
                
                if self?.draft?.testTarget.isEmpty == true, let target = list.targets.first(where: { $0.localizedCaseInsensitiveContains("screenshot") || $0.hasSuffix("UITests") }) {
                    self?.draft?.testTarget = target
                }
            } catch {
                self?.errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
            
            self?.isLoading = false
        }
    }
    
    private func loadSimulators() {
        let runner = runner
        
        Task { [weak self] in
            do {
                let options = try await runner.simulatorOptions()
                self?.deviceTypes = options.devicetypes ?? []
                self?.runtimes = options.runtimes ?? []
            } catch {
                self?.errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }
}
#endif
