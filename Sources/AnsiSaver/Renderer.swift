import AppKit

enum Renderer {

    static func render(ansFileAt path: String, scaleFactor: UInt8 = 1) -> NSImage? {
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
        return NSImage(data: data)
    }
}
