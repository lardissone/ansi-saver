import XCTest

final class AnsiContentValidatorTests: XCTestCase {

    func testBinaryExtensionsAlwaysAccepted() {
        let data = Data("plain ascii without escapes".utf8)
        XCTAssertTrue(AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: "art.ice"))
        XCTAssertTrue(AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: "dump.bin"))
    }

    func testAnsiEscapeAccepted() {
        let data = Data("\u{1b}[0;31mHello\u{1b}[0m\n".utf8)
        XCTAssertTrue(AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: "readme.txt"))
        XCTAssertTrue(AnsiContentValidator.hasAnsiEscapeOrCP437Art(data))
    }

    func testCP437HighBytesAccepted() {
        var bytes = Data()
        // Repeat block-drawing / CP437 bytes (0xB3 = ³ in CP437)
        bytes.append(contentsOf: repeatElement(0xB3, count: 40))
        XCTAssertTrue(AnsiContentValidator.isLikelyAnsiArt(data: bytes, fileName: "border.asc"))
    }

    func testPlainTxtRejectedWithoutAnsiSignals() {
        let prose = """
        RELEASE NOTES

        This is a long readme-style document with many words explaining the archive.
        It continues for several lines with normal prose and no ANSI escape codes.
        """
        let data = Data(prose.utf8)
        XCTAssertFalse(AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: "readme.txt"))
    }

    func testPlainNfoRejectedWithoutAnsiSignals() {
        let nfo = (0..<40).map { _ in
            "NFO LINE: This is typical scene info text without color codes or block characters."
        }.joined(separator: "\n")
        let data = Data(nfo.utf8)
        XCTAssertFalse(AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: "file-id.nfo"))
    }

    func testMislabeledAnsProseRejected() {
        let prose = (0..<50).map { _ in
            "Documentation line that looks like a readme saved with a wrong extension."
        }.joined(separator: "\n")
        let data = Data(prose.utf8)
        XCTAssertFalse(AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: "logo.ans"))
    }

    func testAsciiArtWithoutEscapesStillAccepted() {
        let ascii = """
          ____
         /    \\
        |      |
         \\____/
        """
        let data = Data(ascii.utf8)
        XCTAssertTrue(AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: "pic.asc"))
    }
}
