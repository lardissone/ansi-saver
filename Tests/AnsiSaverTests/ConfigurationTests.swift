import XCTest
import ScreenSaver

final class ConfigurationTests: XCTestCase {

    override func tearDown() {
        let defaults = ScreenSaverDefaults(forModuleWithName: "com.lardissone.AnsiSaver")!
        defaults.removeObject(forKey: "packURLs")
        defaults.removeObject(forKey: "fileURLs")
        defaults.removeObject(forKey: "localFolderBookmark")
        defaults.removeObject(forKey: "transitionMode")
        defaults.removeObject(forKey: "scrollSpeed")
        defaults.removeObject(forKey: "scaleFactor")
        defaults.synchronize()
        super.tearDown()
    }

    func testDefaultValues() {
        let config = Configuration.load()
        XCTAssertTrue(config.packURLs.isEmpty)
        XCTAssertTrue(config.fileURLs.isEmpty)
        XCTAssertNil(config.localFolderBookmark)
        XCTAssertNil(config.localFolderPath)
        XCTAssertEqual(config.transitionMode, 0)
        XCTAssertEqual(config.scrollSpeed, 50.0)
        XCTAssertEqual(config.scaleFactor, 2)
    }

    func testSaveAndLoadURLs() {
        var config = Configuration.load()
        config.packURLs = ["https://16colo.rs/pack/mist0222/"]
        config.fileURLs = ["https://example.com/art.ans"]
        config.transitionMode = 2
        config.scrollSpeed = 100.0
        config.save()

        let loaded = Configuration.load()
        XCTAssertEqual(loaded.packURLs, ["https://16colo.rs/pack/mist0222/"])
        XCTAssertEqual(loaded.fileURLs, ["https://example.com/art.ans"])
        XCTAssertEqual(loaded.transitionMode, 2)
        XCTAssertEqual(loaded.scrollSpeed, 100.0)
    }

    func testBookmarkCreation() {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let bookmark = Configuration.createBookmark(for: tmpURL)
        XCTAssertNotNil(bookmark)
    }
}
