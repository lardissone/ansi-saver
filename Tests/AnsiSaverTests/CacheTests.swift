import XCTest

final class CacheTests: XCTestCase {

    private let testDir = NSTemporaryDirectory() + "AnsiSaverCacheTest/"

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    func testWriteAndRead() {
        let path = testDir + "test/file.ans"
        let data = Data("test content".utf8)

        Cache.write(data, to: path)
        XCTAssertTrue(Cache.exists(path))

        let read = Cache.read(path)
        XCTAssertEqual(read, data)
    }

    func testExistsReturnsFalseForMissingFile() {
        XCTAssertFalse(Cache.exists("/nonexistent/path/file.ans"))
    }

    func testAnsPathForPack() {
        let path = Cache.ansPath(forPack: "mist0222", file: "art.ans")
        XCTAssertTrue(path.contains("packs/mist0222/art.ans"))
    }

    func testPngPathFromAnsPath() {
        let ansPath = "/some/path/art.ans"
        let pngPath = Cache.pngPath(forAnsPath: ansPath)
        XCTAssertEqual(pngPath, "/some/path/art.png")
    }

    func testUrlCachePathIsDeterministic() {
        let url = "https://example.com/art.ans"
        let path1 = Cache.urlCachePath(for: url)
        let path2 = Cache.urlCachePath(for: url)
        XCTAssertEqual(path1, path2)
    }

    func testUrlCachePathDiffersForDifferentURLs() {
        let path1 = Cache.urlCachePath(for: "https://example.com/art1.ans")
        let path2 = Cache.urlCachePath(for: "https://example.com/art2.ans")
        XCTAssertNotEqual(path1, path2)
    }
}
