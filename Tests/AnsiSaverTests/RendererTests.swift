import XCTest

final class RendererTests: XCTestCase {

    func testRenderProducesImageFromValidANS() {
        let fixturePath = fixturesPath().appendingPathComponent("sample.ans").path
        let image = Renderer.render(ansFileAt: fixturePath)
        XCTAssertNotNil(image, "Renderer should produce a non-nil NSImage from a valid .ANS file")
        XCTAssertGreaterThan(image!.size.width, 0)
        XCTAssertGreaterThan(image!.size.height, 0)
    }

    func testRenderReturnsNilForMissingFile() {
        let image = Renderer.render(ansFileAt: "/nonexistent/path/file.ans")
        XCTAssertNil(image)
    }

    func testRenderReturnsNilForEmptyFile() throws {
        let tmp = NSTemporaryDirectory() + "empty_test.ans"
        FileManager.default.createFile(atPath: tmp, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let image = Renderer.render(ansFileAt: tmp)
        XCTAssertNil(image)
    }

    private func fixturesPath() -> URL {
        // Walk up from the build directory to find the source fixtures
        let srcRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        return srcRoot
    }
}
