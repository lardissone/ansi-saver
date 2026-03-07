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
    }

    private var phase: Phase = .idle

    // Continuous scroll state
    private var contentLayer: CALayer?
    private var stackedLayers: [(layer: CALayer, bottomY: CGFloat)] = []
    private var nextContentY: CGFloat = 0
    private var scrollOffset: CGFloat = 0
    private var viewSize: NSSize = .zero
    private var pendingNextArt = false

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
                if contentLayer != nil {
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
        phase = .idle
    }
}
