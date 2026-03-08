import AppKit

struct RenderResult {
    let image: NSImage
    let pixelWidth: Int
    let pixelHeight: Int

    /// Grid dimensions for the given scale factor.
    func gridSize(scaleFactor: Int) -> (columns: Int, rows: Int) {
        let effective = max(scaleFactor, 1)
        return (
            columns: max(pixelWidth / (8 * effective), 1),
            rows: max(pixelHeight / (16 * effective), 1)
        )
    }
}

enum Renderer {

    static func render(ansFileAt path: String, scaleFactor: UInt8 = 0) -> NSImage? {
        return renderWithInfo(ansFileAt: path, scaleFactor: scaleFactor)?.image
    }

    static func renderWithInfo(ansFileAt path: String, scaleFactor: UInt8 = 0) -> RenderResult? {
        var ctx = ansilove_ctx()
        var options = ansilove_options()

        guard ansilove_init(&ctx, &options) == 0 else { return nil }
        defer { ansilove_clean(&ctx) }

        options.font = UInt8(ANSILOVE_FONT_CP437)
        options.bits = 8
        options.icecolors = false
        options.scale_factor = scaleFactor

        guard ansilove_loadfile(&ctx, path) == 0 else { return nil }
        guard ansilove_ansi(&ctx, &options) == 0 else { return nil }
        guard ctx.png.buffer != nil, ctx.png.length > 0 else { return nil }

        let data = Data(bytes: ctx.png.buffer, count: Int(ctx.png.length))
        guard let image = NSImage(data: data) else { return nil }

        // Get actual pixel dimensions from the bitmap representation
        let pixelWidth: Int
        let pixelHeight: Int
        if let rep = image.representations.first {
            pixelWidth = rep.pixelsWide
            pixelHeight = rep.pixelsHigh
        } else {
            pixelWidth = Int(image.size.width)
            pixelHeight = Int(image.size.height)
        }

        return RenderResult(image: image, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    /// Scan the rendered image to find content width (in character columns) per row.
    /// A character cell is considered empty if each of its R, G, B channels is <= 2.
    /// This allows modem simulation to skip trailing blank columns per row.
    static func contentColumnsPerRow(for result: RenderResult, columns: Int, rows: Int) -> [Int] {
        guard columns > 0, rows > 0 else { return [] }
        guard let cgImage = result.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Configuration.debugLog("contentColumnsPerRow: failed to get cgImage")
            return Array(repeating: columns, count: rows)
        }

        let width = result.pixelWidth
        let height = result.pixelHeight
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            Configuration.debugLog("contentColumnsPerRow: CGContext creation failed (width=\(width), height=\(height))")
            return Array(repeating: columns, count: rows)
        }

        // Flip to top-down so row 0 in memory = top of image
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let charWidth = width / columns
        let charHeight = height / rows
        var contentCols = [Int](repeating: 0, count: rows)

        for row in 0..<rows {
            let cellY = row * charHeight
            let cellYEnd = min(cellY + charHeight, height)
            // Scan columns right-to-left; stop at first non-black cell
            for col in stride(from: columns - 1, through: 0, by: -1) {
                let cellX = col * charWidth
                let cellXEnd = min(cellX + charWidth, width)
                var empty = true
                for py in cellY..<cellYEnd {
                    let rowOffset = py * bytesPerRow
                    for px in cellX..<cellXEnd {
                        let offset = rowOffset + px * bytesPerPixel
                        if pixels[offset] > 2 || pixels[offset + 1] > 2 || pixels[offset + 2] > 2 {
                            empty = false
                            break
                        }
                    }
                    if !empty { break }
                }
                if !empty {
                    contentCols[row] = col + 1
                    break
                }
            }
        }

        return contentCols
    }
}
