import XCTest

final class RendererTests: XCTestCase {

    func testRenderProducesImageFromValidANS() throws {
        let fixturePath = fixturesPath().appendingPathComponent("sample.ans").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixturePath),
                      "Fixture file should exist at \(fixturePath)")
        let image = try XCTUnwrap(Renderer.render(ansFileAt: fixturePath),
                                  "Renderer should produce a non-nil NSImage from a valid .ANS file")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testRenderWithInfoProducesPixelDimensions() throws {
        let fixturePath = fixturesPath().appendingPathComponent("sample.ans").path
        let result = try XCTUnwrap(Renderer.renderWithInfo(ansFileAt: fixturePath))
        XCTAssertGreaterThan(result.pixelWidth, 0)
        XCTAssertGreaterThan(result.pixelHeight, 0)
        // CP437 at 8px wide, default 80 columns: width should be multiple of 8
        XCTAssertEqual(result.pixelWidth % 8, 0)
        // CP437 at 16px tall: height should be multiple of 16
        XCTAssertEqual(result.pixelHeight % 16, 0)
    }

    func testContentColumnsPerRow() throws {
        let fixturePath = fixturesPath().appendingPathComponent("sample.ans").path
        let result = try XCTUnwrap(Renderer.renderWithInfo(ansFileAt: fixturePath))
        let columns = result.pixelWidth / 8
        let rows = result.pixelHeight / 16
        let contentCols = Renderer.contentColumnsPerRow(for: result, columns: columns, rows: rows)
        XCTAssertEqual(contentCols.count, rows)
        // Every entry should be between 0 and columns
        for cols in contentCols {
            XCTAssertGreaterThanOrEqual(cols, 0)
            XCTAssertLessThanOrEqual(cols, columns)
        }
        // First row of sample.ans should have visible content
        XCTAssertGreaterThan(contentCols[0], 0, "First row should have visible content")
        // At least some rows should have trailing empty columns
        let hasTrailingBlanks = contentCols.contains(where: { $0 < columns })
        XCTAssertTrue(hasTrailingBlanks, "At least some rows should have trailing empty columns")
    }

    func testGridSize() throws {
        let fixturePath = fixturesPath().appendingPathComponent("sample.ans").path
        let result = try XCTUnwrap(Renderer.renderWithInfo(ansFileAt: fixturePath))
        let (columns, rows) = result.gridSize(scaleFactor: 1)
        XCTAssertGreaterThan(columns, 0)
        XCTAssertGreaterThan(rows, 0)
        XCTAssertEqual(columns, result.pixelWidth / 8)
        XCTAssertEqual(rows, result.pixelHeight / 16)
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
        let srcRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        return srcRoot
    }
}
