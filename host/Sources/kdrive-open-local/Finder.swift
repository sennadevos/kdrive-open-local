import Foundation

/// Hands a path to the Finder.
enum Finder {
    enum Action: String {
        /// Select the item in a Finder window without opening it. Never hydrates an online-only
        /// file and never launches an application.
        case reveal
        /// Open the item with its default application, or open a folder in the Finder.
        case open
    }

    #if os(macOS)
    static func perform(_ action: Action, on path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = action == .reveal ? ["-R", path] : [path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw FinderError.openFailed(status: process.terminationStatus)
        }
    }
    #else
    static func perform(_ action: Action, on path: String) throws {
        throw FinderError.unsupportedPlatform
    }
    #endif

    enum FinderError: Error, CustomStringConvertible {
        case openFailed(status: Int32)
        case unsupportedPlatform

        var description: String {
            switch self {
            case let .openFailed(status): return "/usr/bin/open exited with status \(status)"
            case .unsupportedPlatform: return "opening items in the Finder requires macOS"
            }
        }
    }
}
