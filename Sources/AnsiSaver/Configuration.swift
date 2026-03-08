import Foundation
import ScreenSaver

struct Configuration {

    private static let moduleName = "com.lardissone.AnsiSaver"

    private enum Key {
        static let packURLs = "packURLs"
        static let fileURLs = "fileURLs"
        static let localFolderBookmark = "localFolderBookmark"
        static let transitionMode = "transitionMode"
        static let scrollSpeed = "scrollSpeed"
        static let scaleFactor = "scaleFactor"
        static let continuousScroll = "continuousScroll"
        static let showSeparator = "showSeparator"
        static let displayMode = "displayMode"
        static let modemSpeed = "modemSpeed"
    }

    var packURLs: [String]
    var fileURLs: [String]
    var localFolderBookmark: Data?
    var transitionMode: Int
    var scrollSpeed: Double
    var scaleFactor: Int
    var continuousScroll: Bool
    var showSeparator: Bool
    var displayMode: Int
    var modemSpeed: Int

    var isModemMode: Bool { displayMode == 1 }

    var localFolderPath: String? {
        guard let bookmark = localFolderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return url.path
    }

    static func load() -> Configuration {
        let defaults = screenSaverDefaults()
        let config = Configuration(
            packURLs: defaults.stringArray(forKey: Key.packURLs) ?? ["https://16colo.rs/pack/blocktronics_acid_trip/"],
            fileURLs: defaults.stringArray(forKey: Key.fileURLs) ?? [],
            localFolderBookmark: defaults.data(forKey: Key.localFolderBookmark),
            transitionMode: defaults.integer(forKey: Key.transitionMode),
            scrollSpeed: defaults.object(forKey: Key.scrollSpeed) != nil
                ? defaults.double(forKey: Key.scrollSpeed)
                : 50.0,
            scaleFactor: defaults.object(forKey: Key.scaleFactor) != nil
                ? defaults.integer(forKey: Key.scaleFactor)
                : 2,
            continuousScroll: defaults.bool(forKey: Key.continuousScroll),
            showSeparator: defaults.object(forKey: Key.showSeparator) != nil
                ? defaults.bool(forKey: Key.showSeparator)
                : true,
            displayMode: defaults.integer(forKey: Key.displayMode),
            modemSpeed: defaults.object(forKey: Key.modemSpeed) != nil
                ? defaults.integer(forKey: Key.modemSpeed)
                : 2400
        )
        Self.debugLog("Config.load() process=\(ProcessInfo.processInfo.processName) bookmark=\(config.localFolderBookmark?.count ?? 0) bytes, packs=\(config.packURLs.count), files=\(config.fileURLs.count), folderPath=\(config.localFolderPath ?? "nil")")
        return config
    }

    func save() {
        let defaults = Self.screenSaverDefaults()
        defaults.set(packURLs, forKey: Key.packURLs)
        defaults.set(fileURLs, forKey: Key.fileURLs)
        defaults.set(localFolderBookmark, forKey: Key.localFolderBookmark)
        defaults.set(transitionMode, forKey: Key.transitionMode)
        defaults.set(scrollSpeed, forKey: Key.scrollSpeed)
        defaults.set(scaleFactor, forKey: Key.scaleFactor)
        defaults.set(continuousScroll, forKey: Key.continuousScroll)
        defaults.set(showSeparator, forKey: Key.showSeparator)
        defaults.set(displayMode, forKey: Key.displayMode)
        defaults.set(modemSpeed, forKey: Key.modemSpeed)
        let ok = defaults.synchronize()
        Self.debugLog("Config.save() process=\(ProcessInfo.processInfo.processName) sync=\(ok) bookmark=\(localFolderBookmark?.count ?? 0) bytes, packs=\(packURLs.count)")
    }

    static func debugLog(_ message: String) {
        #if DEBUG
        let entry = "\(Date()): \(message)\n"
        let path = "/tmp/AnsiSaver-debug.log"
        if let handle = FileHandle(forWritingAtPath: path),
           let data = entry.data(using: .utf8) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? entry.write(toFile: path, atomically: true, encoding: .utf8)
        }
        #endif
    }

    static func createBookmark(for url: URL) -> Data? {
        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveBookmark(_ bookmark: Data) -> (path: String, url: URL)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        _ = url.startAccessingSecurityScopedResource()
        return (url.path, url)
    }

    private static func screenSaverDefaults() -> UserDefaults {
        return ScreenSaverDefaults(forModuleWithName: moduleName)!
    }
}
