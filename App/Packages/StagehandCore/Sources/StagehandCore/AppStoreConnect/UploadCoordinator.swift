import Dependencies
import Foundation
import Observation
import OSLog
import StagehandModel

/// Builds an App Store Connect client from the saved credentials, so tests can use a fake.
public struct AppStoreConnectFactory: Sendable {
    public var make: @Sendable (AppStoreConnectCredentials) -> any AppStoreConnectProvider
    
    public init(make: @escaping @Sendable (AppStoreConnectCredentials) -> any AppStoreConnectProvider) {
        self.make = make
    }
}

enum AppStoreConnectFactoryKey: DependencyKey {
    static let liveValue = AppStoreConnectFactory { credentials in
        AppStoreConnectClient(transport: URLSessionTransport(), tokens: AppStoreConnectTokenCache(credentials: credentials, clock: LiveClock()))
    }
    
    static var testValue: AppStoreConnectFactory {
        AppStoreConnectFactory { _ in
            preconditionFailure("Tests provide their own App Store Connect fake")
        }
    }
}

extension DependencyValues {
    public var appStoreConnect: AppStoreConnectFactory {
        get { self[AppStoreConnectFactoryKey.self] }
        set { self[AppStoreConnectFactoryKey.self] = newValue }
    }
}

/// Uploads exports to App Store Connect, always through a plan the user confirms.
///
/// > Warning: Planning is a dry run that only reads. Nothing is uploaded, deleted or reordered until the user
/// > confirms that plan, every time.
@Observable
@MainActor
public final class UploadCoordinator {
    public enum Phase: Equatable {
        case idle
        case planning
        case planned([UploadSetPlan])
        case uploading(done: Int, total: Int)
        case finished(String)
        case failed(String)
    }
    
    public enum Intent {
        case plan
        
        /// The user's explicit yes to the plan on screen.
        case confirmUpload
        case reset
        
        /// Keeps App Store Connect's order (for when it was changed there by hand), and plans again.
        case setKeepsOrder(Bool)
    }
    
    public private(set) var phase: Phase = .idle
    
    /// Adds and replaces screenshots without reordering what's in App Store Connect.
    public private(set) var keepsOrder = false
    
    private let project: ProjectCoordinator
    @ObservationIgnored @Dependency(\.keychain) private var keychain
    @ObservationIgnored @Dependency(\.appStoreConnect) private var factory
    @ObservationIgnored private var provider: (any AppStoreConnectProvider)?
    
    public init(project: ProjectCoordinator) {
        self.project = project
    }
    
    // MARK: - Computed Properties
    
    public var plans: [UploadSetPlan] {
        if case let .planned(plans) = phase { plans } else { [] }
    }
    
    public var totalChanges: (uploads: Int, deletions: Int) {
        (plans.reduce(0) { $0 + $1.uploads.count }, plans.reduce(0) { $0 + $1.deletions.count })
    }
    
    // MARK: - Intents
    
    public func handle(_ intent: Intent) {
        switch intent {
        case .plan:
            Task { await plan() }
        case .confirmUpload:
            let plans = plans
            Task { await upload(plans) }
        case .reset:
            phase = .idle
        case let .setKeepsOrder(keepsOrder):
            self.keepsOrder = keepsOrder
            
            if phase != .idle {
                Task { await plan() }
            }
        }
    }
    
    /// A dry run: reads what's in App Store Connect and compares it with a fresh export.
    public func plan() async {
        phase = .planning
        
        do {
            guard let data = try keychain.read(account: AppStoreConnectCredentials.keychainAccount) else {
                throw AppStoreConnectError.missingCredentials
            }
            
            let credentials = try JSONDecoder().decode(AppStoreConnectCredentials.self, from: data)
            let provider = factory.make(credentials)
            self.provider = provider
            let snapshot = project.project
            
            guard let bundleID = snapshot.bundleID else {
                throw AppStoreConnectError.notFound("The project's bundle identifier (set it in the Set inspector)")
            }
            
            let appID = try await provider.appID(bundleID: bundleID)
            var plans: [UploadSetPlan] = []
            
            for set in snapshot.sets {
                // A Mac target uploads to the macOS version; everything else (Apple Watch included) to iOS's.
                let byPlatform = Dictionary(grouping: set.resolvedTargets()) { $0.deviceClass == .mac ? "MAC_OS" : "IOS" }
                
                for (platform, targets) in byPlatform.sorted(by: { $0.key < $1.key }) {
                    let localizations: [String: ASCLocalization]
                    
                    if let pageID = set.customProductPageID, !pageID.isEmpty {
                        localizations = try await provider.customProductPageLocalizations(pageID: pageID).mapValues { ASCLocalization(id: $0, kind: .customProductPage) }
                    } else {
                        let versionID = try await provider.editableVersionID(appID: appID, platform: platform)
                        localizations = try await provider.localizations(versionID: versionID).mapValues { ASCLocalization(id: $0, kind: .version) }
                    }
                    
                    for locale in snapshot.listingLocales {
                        let localization = localizations[locale]
                        var sets: [String: String] = [:]
                        
                        if let localization {
                            sets = try await provider.screenshotSets(localization: localization)
                        }
                        
                        for target in targets {
                            let setID = sets[target.displayType]
                            var existing: [ASCScreenshot] = []
                            
                            if let setID {
                                existing = try await provider.screenshots(setID: setID)
                            }
                            
                            let desired = try snapshot.slides(in: set, on: target.deviceClass).enumerated().map { index, slide in
                                try render(set: set, slide: slide, target: target, locale: locale, number: index + 1)
                            }
                            
                            plans.append(UploadPlanner.plan(
                                locale: locale,
                                target: target,
                                localization: localization,
                                customProductPageID: set.customProductPageID,
                                setID: setID,
                                desired: desired,
                                existing: existing,
                                keepsOrder: keepsOrder
                            ))
                        }
                    }
                }
            }
            
            phase = .planned(plans)
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }
    
    private func render(set: ShotSet, slide: Slide, target: DeviceTarget, locale: LocaleID, number: Int) throws -> DesiredScreenshot {
        let item = ExportItem(setID: set.id, slideID: slide.id, target: target, locale: locale, number: number, slug: slide.slug)
        
        guard let scene = project.scene(for: CellID(setID: set.id, slideID: slide.id, targetID: target.id), locale: locale) else {
            throw ExportError.renderFailed(item.relativePath)
        }
        
        let data = try SceneRenderer.exportPNG(scene, images: project.images(for: scene), name: item.relativePath)
        return DesiredScreenshot(fileName: (item.relativePath as NSString).lastPathComponent, data: data)
    }
    
    private func upload(_ plans: [UploadSetPlan]) async {
        guard let provider else {
            return
        }
        
        let changed = plans.filter(\.hasChanges)
        let total = changed.reduce(0) { $0 + $1.uploads.count + $1.deletions.count }
        var done = 0
        phase = .uploading(done: 0, total: total)
        
        do {
            for plan in changed {
                guard let localization = plan.localization else {
                    Logger.appStoreConnect.warning("Skipping \(plan.id, privacy: .public): the version has no \(plan.locale, privacy: .public) localization")
                    continue
                }
                
                let setID: String
                
                if let existing = plan.setID {
                    setID = existing
                } else {
                    setID = try await provider.createScreenshotSet(localization: localization, displayType: plan.displayType)
                }
                
                for screenshot in plan.deletions {
                    try await provider.deleteScreenshot(id: screenshot.id)
                    done += 1
                    phase = .uploading(done: done, total: total)
                }
                
                var uploadedIDs: [String: String] = [:]
                
                for screenshot in plan.uploads {
                    let reservation = try await provider.reserveScreenshot(setID: setID, fileName: screenshot.fileName, fileSize: screenshot.data.count)
                    try await provider.uploadParts(screenshot.data, operations: reservation.operations)
                    try await provider.commitScreenshot(id: reservation.id, checksum: screenshot.checksum)
                    uploadedIDs[screenshot.checksum] = reservation.id
                    done += 1
                    phase = .uploading(done: done, total: total)
                }
                
                guard plan.needsReorder else {
                    continue
                }
                
                // TODO: - Wait for App Store Connect to finish processing the uploads before reordering.
                let kept = Dictionary(plan.unchanged.compactMap { shot in shot.checksum.map { ($0, shot.id) } }, uniquingKeysWith: { first, _ in first })
                let order = plan.desired.compactMap { uploadedIDs[$0.checksum] ?? kept[$0.checksum] }
                try await provider.reorderScreenshots(setID: setID, ids: order)
            }
            
            phase = .finished("Uploaded \(changed.reduce(0) { $0 + $1.uploads.count }) screenshots.")
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }
}
