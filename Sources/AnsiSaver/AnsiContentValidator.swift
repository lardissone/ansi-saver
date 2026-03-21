import Foundation

/// Rejects plain documentation text (.txt / .NFO style) while keeping ANSI, CP437 art,
/// and binary formats (ICE, XBin, PCB, etc.) that libansilove renders.
enum AnsiContentValidator {

    /// Returns whether the bytes are likely scene ANSI/CP437 art or a supported binary format,
    /// as opposed to plain text readme / NFO prose.
    static func isLikelyAnsiArt(data: Data, fileName: String) -> Bool {
        guard !data.isEmpty else { return false }

        let ext = (fileName as NSString).pathExtension.lowercased()

        // Binary and container formats — libansilove selects loaders from content; do not filter here.
        if ["ice", "bin", "xb", "pcb", "adf"].contains(ext) {
            return true
        }

        if hasAnsiEscapeOrCP437Art(data) {
            return true
        }

        // Typical readme / info docs without escape codes or CP437 block characters.
        if ["txt", "nfo"].contains(ext) {
            return false
        }

        if looksLikePlainTextProse(data) {
            return false
        }

        return true
    }

    /// ESC sequences or a meaningful amount of CP437 (high-bit) bytes.
    static func hasAnsiEscapeOrCP437Art(_ data: Data) -> Bool {
        let sample = data.prefix(512 * 1024)
        if sample.isEmpty { return false }

        if sample.contains(0x1B) {
            return true
        }

        let highCount = sample.reduce(0) { $0 + ($1 >= 0x80 ? 1 : 0) }
        return Double(highCount) / Double(sample.count) >= 0.004
    }

    /// Heuristic for README-style prose mislabeled as `.ans` / `.asc` (e.g. cached URL saved as `.ans`).
    static func looksLikePlainTextProse(_ data: Data) -> Bool {
        let sample = data.prefix(65_536)
        if sample.contains(0x1B) { return false }

        let highCount = sample.reduce(0) { $0 + ($1 >= 0x80 ? 1 : 0) }
        if sample.count > 0, Double(highCount) / Double(sample.count) >= 0.004 {
            return false
        }

        guard let text = String(data: sample, encoding: .isoLatin1) else { return false }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else { return false }

        var nonWhitespace = 0
        var letters = 0
        for ch in text {
            if ch.isWhitespace { continue }
            nonWhitespace += 1
            if ch.isLetter { letters += 1 }
        }
        guard nonWhitespace > 120 else { return false }

        let letterRatio = Double(letters) / Double(nonWhitespace)
        guard letterRatio > 0.52 else { return false }

        let nonEmptyLines = lines.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return false }
        let totalLen = nonEmptyLines.reduce(0) { $0 + $1.count }
        let avgLineLen = totalLen / nonEmptyLines.count

        return letterRatio > 0.52 && avgLineLen > 42
    }
}
