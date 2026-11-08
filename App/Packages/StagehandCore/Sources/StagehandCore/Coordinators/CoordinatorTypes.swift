import CoreGraphics
import Foundation
import StagehandModel

/// A file dropped or picked by the user.
public struct DroppedFile: Hashable, Sendable {
    public var name: String
    public var data: Data
    
    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// An error to show in an alert.
public struct CoordinatorAlert: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var title: String
    public var message: String
    
    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
    
    public init(title: String, error: any Error) {
        self.init(title: title, message: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
    }
}

/// What the editor is showing and editing.
public struct EditorSelection: Hashable, Sendable {
    public var setID: ShotSet.ID?
    public var slideID: Slide.ID?
    public var targetID: DeviceTarget.ID?
    public var locale: LocaleID
    
    /// The template the template editor shows. While it's set, the canvas edits the template, not the slide.
    public var templateID: TemplateID?
    
    public init(setID: ShotSet.ID? = nil, slideID: Slide.ID? = nil, targetID: DeviceTarget.ID? = nil, locale: LocaleID, templateID: TemplateID? = nil) {
        self.setID = setID
        self.slideID = slideID
        self.targetID = targetID
        self.locale = locale
        self.templateID = templateID
    }
    
    public var cell: CellID? {
        guard let setID, let slideID, let targetID else {
            return nil
        }
        
        return CellID(setID: setID, slideID: slideID, targetID: targetID)
    }
}

/// The contact sheet's rows and columns for one lineup.
public struct ContactSheetState: Hashable, Sendable {
    public struct Column: Hashable, Sendable, Identifiable {
        public var target: DeviceTarget
        
        public var id: DeviceTarget.ID {
            target.id
        }
    }
    
    public struct Group: Hashable, Sendable, Identifiable {
        public var deviceClass: DeviceClass
        public var columns: [Column]
        
        public var id: DeviceClass {
            deviceClass
        }
    }
    
    public struct Row: Hashable, Sendable, Identifiable {
        public var slideID: Slide.ID
        public var number: Int
        public var title: String
        
        /// The other lineups that share this slide.
        public var alsoIn: [String]
        
        /// The devices the slide is off for, whose cells show a "+" instead of a thumbnail.
        public var excludedDevices: Set<DeviceClass>
        
        public var id: Slide.ID {
            slideID
        }
    }
    
    public var setID: ShotSet.ID?
    public var groups: [Group]
    public var rows: [Row]
    public var locale: LocaleID
    public var locales: [LocaleID]
    
    public var columns: [Column] {
        groups.flatMap(\.columns)
    }
}

/// A cell's status for the contact sheet.
public struct CellStatus: Hashable, Sendable {
    public var flags: [SceneFlag]
    public var run: RunCellStatus?
    
    public var severity: SceneFlag.Severity? {
        flags.map(\.severity).max()
    }
}

/// Where a cell's capture run is.
public enum RunCellStatus: Hashable, Sendable {
    case queued
    case capturing
    case captured
    case failed(String)
}
