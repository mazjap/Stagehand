import UniformTypeIdentifiers

extension UTType {
    /// A project package (`.stagehand`).
    public static let stagehandProject = UTType(exportedAs: "com.mazjap.stagehand.project", conformingTo: .package)
    
    /// A style package (`.stagehandstyle`).
    public static let stagehandStyle = UTType(exportedAs: "com.mazjap.stagehand.style", conformingTo: .package)
}
