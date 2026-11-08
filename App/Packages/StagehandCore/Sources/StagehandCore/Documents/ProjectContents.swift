import Foundation
import StagehandModel

/// Everything in a project package. It's also what each undo step restores.
public struct ProjectContents: Hashable, Sendable {
    public var project: Project
    public var captures: CaptureIndex
    
    /// PNG data for each capture in ``captures``.
    public var captureFiles: [CaptureAddress: Data]
    
    /// Font files by file name, from `fonts/`.
    public var fonts: [String: Data]
    
    /// Anything else dropped in, by file name, from `assets/`. Image elements show these.
    public var assets: [String: Data]
    
    /// Copies of the bezels the template set pins, from `bezels/`, so the project opens with the exact bezels it was
    /// made with even when the library's are gone.
    public var bezels: [BezelID: EmbeddedBezel]
    
    public init(
        project: Project,
        captures: CaptureIndex = CaptureIndex(),
        captureFiles: [CaptureAddress: Data] = [:],
        fonts: [String: Data] = [:],
        assets: [String: Data] = [:],
        bezels: [BezelID: EmbeddedBezel] = [:]
    ) {
        self.project = project
        self.captures = captures
        self.captureFiles = captureFiles
        self.fonts = fonts
        self.assets = assets
        self.bezels = bezels
    }
}

/// A bezel copied into a document: its `bezel.json` and image.
public struct EmbeddedBezel: Hashable, Sendable {
    public var info: BezelInfo
    public var png: Data
    
    public init(info: BezelInfo, png: Data) {
        self.info = info
        self.png = png
    }
}
