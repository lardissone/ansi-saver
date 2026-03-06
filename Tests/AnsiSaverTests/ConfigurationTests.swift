import XCTest

final class ConfigurationTests: XCTestCase {

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: "com.lardissone.AnsiSaver") {
            defaults.removePersistentDomain(forName: "com.lardissone.AnsiSaver")
        }
        super.tearDown()
    }

    func testDefaultValues() {
        let config = Configuration.load()
        XCTAssertTrue(config.packURLs.isEmpty)
        XCTAssertTrue(config.fileURLs.isEmpty)
        XCTAssertNil(config.localFolderPath)
        XCTAssertEqual(config.transitionMode, 0)
        XCTAssertEqual(config.scrollSpeed, 50.0)
    }

    func testSaveAndLoad() {
        var config = Configuration.load()
        config.packURLs = ["https://16colo.rs/pack/mist0222/"]
        config.fileURLs = ["https://example.com/art.ans"]
        config.localFolderPath = "/tmp/ansi"
        config.transitionMode = 2
        config.scrollSpeed = 100.0
        config.save()

        let loaded = Configuration.load()
        XCTAssertEqual(loaded.packURLs, ["https://16colo.rs/pack/mist0222/"])
        XCTAssertEqual(loaded.fileURLs, ["https://example.com/art.ans"])
        XCTAssertEqual(loaded.localFolderPath, "/tmp/ansi")
        XCTAssertEqual(loaded.transitionMode, 2)
        XCTAssertEqual(loaded.scrollSpeed, 100.0)
    }
}
