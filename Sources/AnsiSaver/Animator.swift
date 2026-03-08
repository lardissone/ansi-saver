import AppKit
import QuartzCore

enum TransitionMode: Int {
    case scrollUp = 0
    case scrollDown = 1
    case crossfade = 2
}

class Animator {

    private weak var containerLayer: CALayer?
    private var currentLayer: CALayer?
    private var oldLayer: CALayer?

    private var scrollSpeed: CGFloat = 0
    private var scrollDirection: CGFloat = 1
    private var scrollEndY: CGFloat = 0

    private enum Phase {
        case idle
        case crossfading(until: CFTimeInterval)
        case startPause(until: CFTimeInterval)
        case scrolling
        case displaying(until: CFTimeInterval)
        case endPause(until: CFTimeInterval)
        case continuousScrolling
        case modemRevealing
    }

    private var phase: Phase = .idle

    // Continuous scroll state
    private var contentLayer: CALayer?
    private var stackedLayers: [(layer: CALayer, bottomY: CGFloat)] = []
    private var nextContentY: CGFloat = 0
    private var scrollOffset: CGFloat = 0
    private var viewSize: NSSize = .zero
    private var pendingNextArt = false

    // Modem simulation state
    private var modemCharPosition: CGFloat = 0
    private var modemColumns: Int = 80
    private var modemRows: Int = 25
    private var modemDisplayCharWidth: CGFloat = 0
    private var modemDisplayCharHeight: CGFloat = 0
    private var modemCharsPerFrame: CGFloat = 0
    private var modemTotalChars: Int = 0
    private var modemMaskLayer: CAShapeLayer?
    private var modemFitHeight: CGFloat = 0
    private var modemContentCols: [Int] = []      // actual content width per row
    private var modemCumulativeChars: [Int] = []  // cumulative char offsets per row
    private var modemImageStartY: CGFloat = 0     // top of current image in content stack

    var onAnimationComplete: (() -> Void)?
    var onNeedNextArt: ((_ callback: @escaping (NSImage, String) -> Void) -> Void)?

    init(containerLayer: CALayer) {
        self.containerLayer = containerLayer
        containerLayer.masksToBounds = true
    }

    // MARK: - Standard mode

    func display(image: NSImage, transition: TransitionMode, speed: Double, viewSize: NSSize) {
        guard let container = containerLayer else { return }
        self.viewSize = viewSize

        let imageSize = image.size
        let scaleX = viewSize.width / imageSize.width
        let fitWidth = imageSize.width * scaleX
        let fitHeight = imageSize.height * scaleX

        let newLayer = CALayer()
        newLayer.contents = image
        newLayer.contentsGravity = .resize
        newLayer.frame = CGRect(
            x: (viewSize.width - fitWidth) / 2,
            y: 0,
            width: fitWidth,
            height: fitHeight
        )

        let hasPrevious = currentLayer != nil
        oldLayer?.removeFromSuperlayer()
        oldLayer = currentLayer
        currentLayer = newLayer
        newLayer.opacity = hasPrevious ? 0 : 1
        container.addSublayer(newLayer)

        let totalScroll = max(fitHeight - viewSize.height, 0)

        if totalScroll <= 0 {
            newLayer.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
            let displayDuration: CFTimeInterval
            if case .crossfade = transition {
                displayDuration = max(5.0, 20.0 - speed / 10.0)
            } else {
                displayDuration = 8.0
            }
            scrollSpeed = 0
            scrollEndY = CGFloat(displayDuration)
            if hasPrevious {
                phase = .crossfading(until: CACurrentMediaTime() + 1.5)
            } else {
                newLayer.opacity = 1
                phase = .displaying(until: CACurrentMediaTime() + displayDuration)
            }
            return
        }

        let startY = viewSize.height - fitHeight / 2
        let endY = fitHeight / 2

        switch transition {
        case .scrollUp, .crossfade:
            newLayer.position = CGPoint(x: newLayer.frame.midX, y: startY)
            scrollEndY = endY
            scrollDirection = 1
        case .scrollDown:
            newLayer.position = CGPoint(x: newLayer.frame.midX, y: endY)
            scrollEndY = startY
            scrollDirection = -1
        }

        scrollSpeed = CGFloat(max(speed, 1))
        if hasPrevious {
            phase = .crossfading(until: CACurrentMediaTime() + 1.5)
        } else {
            phase = .startPause(until: CACurrentMediaTime() + 2.0)
        }
    }

    // MARK: - Modem simulation mode

    func displayModem(image: NSImage, columns: Int, rows: Int, contentColumnsPerRow: [Int], modemSpeed: Int, viewSize: NSSize) {
        guard let container = containerLayer else { return }
        self.viewSize = viewSize

        stopAnimations()

        let imageSize = image.size
        let scaleX = viewSize.width / imageSize.width
        let fitWidth = imageSize.width * scaleX
        let fitHeight = imageSize.height * scaleX

        let newLayer = CALayer()
        newLayer.contents = image
        newLayer.contentsGravity = .resize
        newLayer.frame = CGRect(
            x: (viewSize.width - fitWidth) / 2,
            y: 0,
            width: fitWidth,
            height: fitHeight
        )

        // Position image with top at top of view
        newLayer.position = CGPoint(
            x: newLayer.frame.midX,
            y: viewSize.height - fitHeight / 2
        )

        // Create mask layer (initially empty — nothing visible)
        let mask = CAShapeLayer()
        mask.frame = newLayer.bounds
        newLayer.mask = mask

        container.addSublayer(newLayer)
        currentLayer = newLayer
        modemMaskLayer = mask

        modemColumns = max(columns, 1)
        modemRows = max(rows, 1)
        modemDisplayCharWidth = fitWidth / CGFloat(modemColumns)
        modemDisplayCharHeight = fitHeight / CGFloat(modemRows)
        modemCharsPerFrame = CGFloat(modemSpeed) / 10.0 / 60.0
        modemCharPosition = 0
        modemFitHeight = fitHeight

        // Build per-row content widths and cumulative char offsets.
        // Each row costs max(contentCols, 1) effective chars — the 1 accounts
        // for CR/LF on fully empty rows.
        modemContentCols = contentColumnsPerRow
        modemCumulativeChars = [Int](repeating: 0, count: modemRows + 1)
        for r in 0..<modemRows {
            let rowChars = r < modemContentCols.count ? max(modemContentCols[r], 1) : modemColumns
            modemCumulativeChars[r + 1] = modemCumulativeChars[r] + rowChars
        }
        modemTotalChars = modemCumulativeChars[modemRows]

        phase = .startPause(until: CACurrentMediaTime() + 1.0)
    }

    func startModemContinuous(firstImage: NSImage, columns: Int, rows: Int, contentColumnsPerRow: [Int], modemSpeed: Int, viewSize: NSSize) {
        guard let container = containerLayer else { return }
        self.viewSize = viewSize

        stopAnimations()

        let content = CALayer()
        content.masksToBounds = false
        container.addSublayer(content)
        contentLayer = content

        nextContentY = 0
        scrollOffset = 0
        stackedLayers = []
        pendingNextArt = false

        modemCharsPerFrame = CGFloat(modemSpeed) / 10.0 / 60.0

        appendModemArt(image: firstImage, columns: columns, rows: rows, contentColumnsPerRow: contentColumnsPerRow)
        phase = .startPause(until: CACurrentMediaTime() + 1.0)
    }

    func appendModemArt(image: NSImage, columns: Int, rows: Int, contentColumnsPerRow: [Int]) {
        guard let content = contentLayer else { return }

        let imageSize = image.size
        let scaleX = viewSize.width / imageSize.width
        let fitWidth = imageSize.width * scaleX
        let fitHeight = imageSize.height * scaleX

        let artLayer = CALayer()
        artLayer.contents = image
        artLayer.contentsGravity = .resize
        artLayer.frame = CGRect(
            x: (viewSize.width - fitWidth) / 2,
            y: -nextContentY - fitHeight,
            width: fitWidth,
            height: fitHeight
        )

        let mask = CAShapeLayer()
        mask.frame = artLayer.bounds
        artLayer.mask = mask

        content.addSublayer(artLayer)

        modemImageStartY = nextContentY
        let bottomY = nextContentY + fitHeight
        stackedLayers.append((layer: artLayer, bottomY: bottomY))
        nextContentY = bottomY

        currentLayer = artLayer
        modemMaskLayer = mask
        modemColumns = max(columns, 1)
        modemRows = max(rows, 1)
        modemDisplayCharWidth = fitWidth / CGFloat(modemColumns)
        modemDisplayCharHeight = fitHeight / CGFloat(modemRows)
        modemCharPosition = 0
        modemFitHeight = fitHeight

        modemContentCols = contentColumnsPerRow
        modemCumulativeChars = [Int](repeating: 0, count: modemRows + 1)
        for r in 0..<modemRows {
            let rowChars = r < modemContentCols.count ? max(modemContentCols[r], 1) : modemColumns
            modemCumulativeChars[r + 1] = modemCumulativeChars[r] + rowChars
        }
        modemTotalChars = modemCumulativeChars[modemRows]

        pendingNextArt = false
        phase = .modemRevealing
    }

    private func tickModemReveal() {
        guard let layer = currentLayer, let mask = modemMaskLayer else {
            phase = .idle
            return
        }

        modemCharPosition += modemCharsPerFrame
        let charIndex = min(Int(modemCharPosition), modemTotalChars)

        if charIndex >= modemTotalChars {
            // Fully revealed — remove mask, pause with jitter before next file
            layer.mask = nil
            modemMaskLayer = nil
            let jitter = Double.random(in: 0...1.0)
            phase = .endPause(until: CACurrentMediaTime() + 2.0 + jitter)
            return
        }

        // Map linear char position to (row, col) using cumulative offsets.
        // Each row has a variable effective width based on actual content.
        var row = 0
        for r in 0..<modemRows {
            if charIndex < modemCumulativeChars[r + 1] {
                row = r
                break
            }
        }
        let colInRow = charIndex - modemCumulativeChars[row]
        // Clamp col to the content width for this row (the extra 1 for CR/LF
        // shouldn't extend the visible reveal beyond the content)
        let rowContent = row < modemContentCols.count ? modemContentCols[row] : modemColumns
        let col = min(colInRow, rowContent)

        let dch = modemDisplayCharHeight
        let dcw = modemDisplayCharWidth
        let fitHeight = modemFitHeight
        let fitWidth = layer.bounds.width

        // Build reveal mask path
        let path = CGMutablePath()

        // Fully revealed rows above current row (full width — trailing black
        // is already black, so revealing it is invisible)
        if row > 0 {
            path.addRect(CGRect(
                x: 0,
                y: fitHeight - CGFloat(row) * dch,
                width: fitWidth,
                height: CGFloat(row) * dch
            ))
        }

        // Partial current row
        if col > 0 {
            path.addRect(CGRect(
                x: 0,
                y: fitHeight - CGFloat(row + 1) * dch,
                width: CGFloat(col) * dcw,
                height: dch
            ))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.path = path

        // Scroll content layer to keep cursor visible
        if let content = contentLayer {
            let cursorAbsY = modemImageStartY + CGFloat(row + 1) * dch
            content.bounds.origin.y = -max(viewSize.height, cursorAbsY)
            scrollOffset = max(0, cursorAbsY - viewSize.height)

            // Remove layers that scrolled off the top
            while let first = stackedLayers.first, first.bottomY < scrollOffset {
                first.layer.removeFromSuperlayer()
                stackedLayers.removeFirst()
            }
        }
        CATransaction.commit()
    }

    // MARK: - Continuous scroll mode

    func startContinuousScroll(firstImage: NSImage, fileName: String, speed: Double, viewSize: NSSize, showSeparator: Bool) {
        guard let container = containerLayer else { return }
        self.viewSize = viewSize
        scrollSpeed = CGFloat(max(speed, 1))

        stopAnimations()

        let content = CALayer()
        content.masksToBounds = false
        container.addSublayer(content)
        contentLayer = content

        nextContentY = 0
        scrollOffset = 0
        stackedLayers = []
        pendingNextArt = false

        appendArt(image: firstImage, fileName: fileName, showSeparator: false)
        phase = .startPause(until: CACurrentMediaTime() + 2.0)
    }

    func appendArt(image: NSImage, fileName: String, showSeparator: Bool) {
        guard let content = contentLayer else { return }

        if showSeparator && nextContentY > 0 {
            let sep = createSeparator(fileName: fileName, width: viewSize.width)
            sep.frame = CGRect(x: 0, y: -nextContentY - sep.bounds.height, width: viewSize.width, height: sep.bounds.height)
            content.addSublayer(sep)
            nextContentY += sep.bounds.height
        }

        let scaleX = viewSize.width / image.size.width
        let fitWidth = image.size.width * scaleX
        let fitHeight = image.size.height * scaleX

        let artLayer = CALayer()
        artLayer.contents = image
        artLayer.contentsGravity = .resize
        artLayer.frame = CGRect(
            x: (viewSize.width - fitWidth) / 2,
            y: -nextContentY - fitHeight,
            width: fitWidth,
            height: fitHeight
        )
        content.addSublayer(artLayer)

        let bottomY = nextContentY + fitHeight
        stackedLayers.append((layer: artLayer, bottomY: bottomY))
        nextContentY = bottomY

        pendingNextArt = false
    }

    private func createSeparator(fileName: String, width: CGFloat) -> CALayer {
        let height: CGFloat = 80
        let separator = CALayer()
        separator.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        separator.backgroundColor = NSColor(white: 0.05, alpha: 1).cgColor

        // Top decorative line
        let topLine = CALayer()
        topLine.frame = CGRect(x: width * 0.1, y: height - 24, width: width * 0.8, height: 1)
        topLine.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        separator.addSublayer(topLine)

        // Filename label
        let label = CATextLayer()
        let displayName = (fileName as NSString).deletingPathExtension.uppercased()
        label.string = "· \(displayName) ·"
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium) as CTFont
        label.fontSize = 11
        label.foregroundColor = NSColor(white: 0.4, alpha: 1).cgColor
        label.alignmentMode = .center
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        label.frame = CGRect(x: 0, y: (height - 14) / 2, width: width, height: 14)
        separator.addSublayer(label)

        // Bottom decorative line
        let bottomLine = CALayer()
        bottomLine.frame = CGRect(x: width * 0.1, y: 24, width: width * 0.8, height: 1)
        bottomLine.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        separator.addSublayer(bottomLine)

        // Small diamond accents
        for xPos in [width * 0.1, width * 0.9 - 4] {
            let diamond = CALayer()
            diamond.frame = CGRect(x: xPos, y: height - 27, width: 5, height: 5)
            diamond.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
            diamond.transform = CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
            separator.addSublayer(diamond)

            let diamond2 = CALayer()
            diamond2.frame = CGRect(x: xPos, y: 21, width: 5, height: 5)
            diamond2.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
            diamond2.transform = CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
            separator.addSublayer(diamond2)
        }

        return separator
    }

    // MARK: - Tick

    func tick() {
        switch phase {
        case .idle:
            return

        case .crossfading(let until):
            let remaining = until - CACurrentMediaTime()
            let progress = Float(max(0, min(1, 1.0 - remaining / 1.5)))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            currentLayer?.opacity = progress
            oldLayer?.opacity = 1.0 - progress
            CATransaction.commit()
            if remaining <= 0 {
                oldLayer?.removeFromSuperlayer()
                oldLayer = nil
                currentLayer?.opacity = 1
                if scrollSpeed > 0 {
                    phase = .startPause(until: CACurrentMediaTime() + 0.5)
                } else {
                    let displayDuration = CFTimeInterval(scrollEndY)
                    phase = .displaying(until: CACurrentMediaTime() + displayDuration)
                }
            }

        case .startPause(let until):
            if CACurrentMediaTime() >= until {
                oldLayer?.removeFromSuperlayer()
                oldLayer = nil
                if modemMaskLayer != nil {
                    phase = .modemRevealing
                } else if contentLayer != nil {
                    phase = .continuousScrolling
                } else {
                    phase = .scrolling
                }
            }

        case .scrolling:
            guard let layer = currentLayer else {
                phase = .idle
                return
            }
            let step = scrollSpeed / 60.0 * scrollDirection
            let newY = layer.position.y + step

            let done: Bool
            if scrollDirection > 0 {
                done = newY >= scrollEndY
            } else {
                done = newY <= scrollEndY
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if done {
                layer.position.y = scrollEndY
                phase = .endPause(until: CACurrentMediaTime() + 2.0)
            } else {
                layer.position.y = newY
            }
            CATransaction.commit()

        case .modemRevealing:
            tickModemReveal()

        case .continuousScrolling:
            guard let content = contentLayer else {
                phase = .idle
                return
            }

            let step = scrollSpeed / 60.0
            scrollOffset += step

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content.bounds.origin.y = -scrollOffset
            CATransaction.commit()

            // Remove layers that scrolled off the top
            while let first = stackedLayers.first, first.bottomY < scrollOffset - viewSize.height {
                first.layer.removeFromSuperlayer()
                stackedLayers.removeFirst()
            }

            // Request next art when approaching the bottom
            let remainingContent = nextContentY - scrollOffset - viewSize.height
            if remainingContent < viewSize.height * 2 && !pendingNextArt {
                pendingNextArt = true
                onAnimationComplete?()
            }

            // If we've scrolled past all content, go idle
            if scrollOffset >= nextContentY - viewSize.height && stackedLayers.isEmpty {
                phase = .idle
            }

        case .displaying(let until):
            if CACurrentMediaTime() >= until {
                phase = .idle
                onAnimationComplete?()
            }

        case .endPause(let until):
            if CACurrentMediaTime() >= until {
                phase = .idle
                onAnimationComplete?()
            }
        }
    }

    func stopAnimations() {
        currentLayer?.removeFromSuperlayer()
        oldLayer?.removeFromSuperlayer()
        contentLayer?.removeFromSuperlayer()
        currentLayer = nil
        oldLayer = nil
        contentLayer = nil
        stackedLayers = []
        pendingNextArt = false
        modemMaskLayer = nil
        modemImageStartY = 0
        phase = .idle
    }
}
