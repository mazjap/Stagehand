import OSLog

extension Logger {
    static let subsystem = "com.mazjap.Stagehand"
    
    static let documents = Logger(subsystem: subsystem, category: "Documents")
    static let export = Logger(subsystem: subsystem, category: "Export")
    static let runner = Logger(subsystem: subsystem, category: "Runner")
    static let bezels = Logger(subsystem: subsystem, category: "Bezels")
    static let fonts = Logger(subsystem: subsystem, category: "Fonts")
    static let library = Logger(subsystem: subsystem, category: "Library")
    static let appStoreConnect = Logger(subsystem: subsystem, category: "AppStoreConnect")
}
