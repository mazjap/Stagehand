import CoreGraphics
import Foundation
import StagehandModel

/// A bezel's `bezel.json`: where its screen is, and what it's for.
public struct BezelInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: BezelID
    public var name: String
    public var deviceClass: DeviceClass
    public var model: String
    public var color: String
    public var imageWidth: Int
    public var imageHeight: Int
    
    /// The screen's bounding box in the bezel image, in pixels from the top left.
    public var screenRect: PixelRect
    
    /// When it was imported. An updated file from Apple is imported next to the old one, so the later one is newer.
    public var importedAt: Date?
    
    /// Where it was downloaded from, for bezels from Apple Design Resources.
    public var source: BezelSourceInfo?
    
    public init(
        id: BezelID,
        name: String,
        deviceClass: DeviceClass,
        model: String,
        color: String,
        imageWidth: Int,
        imageHeight: Int,
        screenRect: PixelRect,
        importedAt: Date? = nil,
        source: BezelSourceInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceClass = deviceClass
        self.model = model
        self.color = color
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.screenRect = screenRect
        self.importedAt = importedAt
        self.source = source
    }
    
    // MARK: - Computed Properties
    
    /// The model and color, like "iPhone 18 Pro Max, Cosmic Orange".
    public var displayName: String {
        [model.isEmpty ? name : model, color].filter { !$0.isEmpty }.joined(separator: ", ")
    }
    
    /// The screen's width over its height.
    public var screenAspectRatio: Double {
        Double(screenRect.width) / Double(max(screenRect.height, 1))
    }
    
    /// The model's generation: its first number, like 18 in "iPhone 18 Pro Max" or 5 in "iPad Pro (M5)".
    public var generation: Int? {
        Self.firstNumber(in: model.isEmpty ? name : model)
    }
    
    /// The model without its generation, like "iphone pro max", so models of one size in different years match.
    public var productLine: String {
        let model = (model.isEmpty ? name : model).lowercased()
        let withoutNumber = model.replacing(#/\d+/#, with: "", maxReplacements: 1)
        return withoutNumber.split(whereSeparator: { !$0.isLetter }).joined(separator: " ")
    }
    
    /// What switching to another bezel changes that can move a layout.
    public enum Change: Hashable, Sendable {
        /// The screen's aspect ratio differs by more than 1%.
        case screenShape
        
        /// The frame around the screen differs: the screen's share of the width, or the image's shape, by more than 1%.
        case frameSize
    }
    
    public func changes(to new: BezelInfo) -> [Change] {
        var changes: [Change] = []
        
        if abs(new.screenAspectRatio - screenAspectRatio) / screenAspectRatio > 0.01 {
            changes.append(.screenShape)
        }
        
        let oldFrame = Double(screenRect.width) / Double(imageWidth)
        let newFrame = Double(new.screenRect.width) / Double(new.imageWidth)
        let oldShape = Double(imageHeight) / Double(imageWidth)
        let newShape = Double(new.imageHeight) / Double(new.imageWidth)
        
        if abs(newFrame - oldFrame) > 0.01 || abs(newShape - oldShape) / oldShape > 0.01 {
            changes.append(.frameSize)
        }
        
        return changes
    }
    
    static func firstNumber(in string: String) -> Int? {
        string.firstMatch(of: #/\d+/#).flatMap { Int($0.output) }
    }
    
    /// The image for drawing the bezel.
    public var imageRef: ImageRef {
        ImageRef("bezel:\(id)")
    }
    
    /// The screen's mask: the flood-filled region, opaque where the capture shows.
    public var maskRef: ImageRef {
        ImageRef("bezel-mask:\(id)")
    }
}

/// A rectangle in whole pixels, from the top left.
public struct PixelRect: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// The bezels a resolve can use: the library's, and its default for each class.
public struct BezelCatalog: Hashable, Sendable {
    public var bezels: [BezelID: BezelInfo]
    public var defaults: [DeviceClass: BezelID]
    
    public init(bezels: [BezelID: BezelInfo] = [:], defaults: [DeviceClass: BezelID] = [:]) {
        self.bezels = bezels
        self.defaults = defaults
    }
    
    public static let empty = BezelCatalog()
    
    /// The catalog with a document's embedded bezels laid over it.
    public func merging(embedded: [BezelID: EmbeddedBezel]) -> BezelCatalog {
        var merged = self
        
        for (id, bezel) in embedded {
            merged.bezels[id] = bezel.info
        }
        
        return merged
    }
    
    // MARK: - Functions
    
    /// A newer bezel for a pinned one: the same product line on the same class with a higher generation (iPhone 18 Pro
    /// Max to iPhone 19 Pro Max), or the same model and color imported later (an updated file from Apple). The newest.
    public func newerBezel(than id: BezelID) -> BezelInfo? {
        guard let pinned = bezels[id] else {
            return nil
        }
        
        let candidates = bezels.values.filter { candidate in
            guard candidate.id != pinned.id, candidate.deviceClass == pinned.deviceClass, candidate.productLine == pinned.productLine else {
                return false
            }
            
            let generation = candidate.generation ?? 0
            let pinnedGeneration = pinned.generation ?? 0
            
            if generation != pinnedGeneration {
                return generation > pinnedGeneration
            }
            
            return candidate.model == pinned.model && candidate.color == pinned.color
                && (candidate.importedAt ?? .distantPast) > (pinned.importedAt ?? .distantPast)
        }
        
        return candidates.max { lhs, rhs in
            (lhs.generation ?? 0, lhs.importedAt ?? .distantPast) < (rhs.generation ?? 0, rhs.importedAt ?? .distantPast)
        }
    }
    
    /// The bezel to pin on a class: of those whose screen's shape is closest to the aspect ratio (within 3%), the
    /// class's default, or else the newest, and of the newest, the closest shape (so an iPhone 18 Pro Max, whose
    /// screen is the 6.9-inch size exactly, beats an iPhone 18 Pro for it). Without an aspect ratio, the default or
    /// the newest.
    public func bestBezel(for device: DeviceClass, aspectRatio: Double?) -> BezelInfo? {
        var candidates = bezels.values.filter { $0.deviceClass == device }
        
        if let aspectRatio, !candidates.isEmpty {
            let closest = candidates.map { abs($0.screenAspectRatio - aspectRatio) / aspectRatio }.min() ?? 0
            candidates = candidates.filter { abs($0.screenAspectRatio - aspectRatio) / aspectRatio <= max(closest, 0.03) }
        }
        
        if let id = defaults[device], let bezel = candidates.first(where: { $0.id == id }) {
            return bezel
        }
        
        // NOTE: - Closeness is compared negated, so a closer shape ranks higher; the ID last keeps the choice stable.
        let distance = { (bezel: BezelInfo) in aspectRatio.map { -abs(bezel.screenAspectRatio - $0) } ?? 0 }
        
        return candidates.max { lhs, rhs in
            (lhs.generation ?? 0, distance(lhs), lhs.importedAt ?? .distantPast, rhs.id) < (rhs.generation ?? 0, distance(rhs), rhs.importedAt ?? .distantPast, lhs.id)
        }
    }
    
    /// The bezel a choice draws for a class, or `nil` for none or a missing bezel. Library Default without a default
    /// for the class draws the best match for the screen's shape.
    public func bezel(for choice: BezelChoice, deviceClass: DeviceClass, aspectRatio: Double? = nil) -> BezelInfo? {
        switch choice {
        case .matchTarget: defaults[deviceClass].flatMap { bezels[$0] } ?? bestBezel(for: deviceClass, aspectRatio: aspectRatio)
        case let .pinned(id): bezels[id]
        case .none: nil
        }
    }
}

/// Where a downloaded bezel came from.
public struct BezelSourceInfo: Codable, Hashable, Sendable {
    /// The disk image's URL on Apple Design Resources.
    public var url: URL
    
    /// The product it was listed as, like "iPhone 18".
    public var product: String
    
    /// The file's `ETag` (or `Last-Modified`) when it was downloaded, to notice an updated file.
    public var version: String?
    
    public init(url: URL, product: String, version: String?) {
        self.url = url
        self.product = product
        self.version = version
    }
}
