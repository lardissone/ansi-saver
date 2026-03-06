import XCTest

final class PackFetcherTests: XCTestCase {

    func testParseANSFilenamesFromHTML() {
        let html = """
        <html>
        <body>
        <a href="/pack/mist0222/raw/ms-mist.ans">ms-mist.ans</a>
        <a href="/pack/mist0222/raw/ms-logo.ANS">ms-logo.ANS</a>
        <a href="/pack/mist0222/raw/readme.txt">readme.txt</a>
        <a href="/pack/mist0222/raw/art.ice">art.ice</a>
        <a href="/pack/mist0222/FILE_ID.DIZ">FILE_ID.DIZ</a>
        </body>
        </html>
        """

        let filenames = PackFetcher.parseANSFilenames(from: html)
        XCTAssertEqual(filenames.count, 3)
        XCTAssertTrue(filenames.contains("ms-mist.ans"))
        XCTAssertTrue(filenames.contains("ms-logo.ANS"))
        XCTAssertTrue(filenames.contains("art.ice"))
    }

    func testParseANSFilenamesDeduplicates() {
        let html = """
        <a href="/pack/test/raw/file.ans">file.ans</a>
        <a href="/pack/test/raw/file.ans">file.ans</a>
        """

        let filenames = PackFetcher.parseANSFilenames(from: html)
        XCTAssertEqual(filenames.count, 1)
    }

    func testParseANSFilenamesReturnsEmptyForNoMatches() {
        let html = "<html><body>No art here</body></html>"
        let filenames = PackFetcher.parseANSFilenames(from: html)
        XCTAssertTrue(filenames.isEmpty)
    }
}
