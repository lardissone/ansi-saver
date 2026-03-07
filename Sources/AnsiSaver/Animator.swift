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

    private var scrollStartY: CGFloat = 0
    private var scrollEndY: CGFloat = 0
    private var scrollSpeed: CGFloat = 0
    private var scrollDirection: CGFloat = 1

    private enum Phase {
        case idle
        case startPause(until: CFTimeInterval)
        case scrolling
        case fadingIn(until: CFTimeInterval)
        case displaying(until: CFTimeInterval)
        case endPause(until: CFTimeInterval)
    }

    private var phase: Phase = .idle

    var onAnimationComplete: (() -> Void)?

    init(containerLayer: CALayer) {
        self.containerLayer = containerLayer
        containerLayer.masksToBounds = true
    }

    func display(image: NSImage, transition: TransitionMode, speed: Double, viewSize: NSSize) {
        guard let container = containerLayer else { return }

        let imageSize = image.size
        let scaleX = viewSize.width / imageSize.width
        let fitWidth = imageSize.width * scaleX
        let fitHeight = imageSize.height * scaleX
        Configuration.debugLog("Animator.display: imageSize=\(imageSize) viewSize=\(viewSize) fitHeight=\(fitHeight) transition=\(transition.rawValue) speed=\(speed)")

        let newLayer = CALayer()
        newLayer.contents = image
        newLayer.contentsGravity = .resize
        newLayer.frame = CGRect(
            x: (viewSize.width - fitWidth) / 2,
            y: 0,
            width: fitWidth,
            height: fitHeight
        )

        oldLayer?.removeFromSuperlayer()
        oldLayer = currentLayer
        currentLayer = newLayer
        container.addSublayer(newLayer)

        let totalScroll = max(fitHeight - viewSize.height, 0)

        if totalScroll <= 0 {
            // Image fits in view — center it and display with pause
            newLayer.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
            newLayer.opacity = 0
            let displayDuration: CFTimeInterval
            if case .crossfade = transition {
                displayDuration = max(5.0, 20.0 - speed / 10.0)
            } else {
                displayDuration = 8.0
            }
            phase = .fadingIn(until: CACurrentMediaTime() + 2.0)
            scrollSpeed = 0
            Configuration.debugLog("Animator: image fits, fadingIn then display for \(displayDuration)s")
            // Store display duration for use after fade completes
            scrollEndY = CGFloat(displayDuration)
            return
        }

        // Scroll setup: position so top of image aligns with top of view
        let startY = viewSize.height - fitHeight / 2
        let endY = fitHeight / 2

        switch transition {
        case .scrollUp:
            newLayer.position = CGPoint(x: newLayer.frame.midX, y: startY)
            scrollStartY = startY
            scrollEndY = endY
            scrollDirection = 1
        case .scrollDown:
            newLayer.position = CGPoint(x: newLayer.frame.midX, y: endY)
            scrollStartY = endY
            scrollEndY = startY
            scrollDirection = -1
        case .crossfade:
            newLayer.position = CGPoint(x: newLayer.frame.midX, y: startY)
            scrollStartY = startY
            scrollEndY = endY
            scrollDirection = 1
        }

        scrollSpeed = CGFloat(max(speed, 1))
        phase = .startPause(until: CACurrentMediaTime() + 2.0)
        Configuration.debugLog("Animator: scroll totalScroll=\(totalScroll) duration=\(totalScroll / scrollSpeed)s")
    }

    /// Called each frame from animateOneFrame()
    func tick() {
        switch phase {
        case .idle:
            return

        case .startPause(let until):
            if CACurrentMediaTime() >= until {
                oldLayer?.removeFromSuperlayer()
                oldLayer = nil
                phase = .scrolling
            }

        case .scrolling:
            guard let layer = currentLayer else {
                phase = .idle
                return
            }
            let currentY = layer.position.y
            let step = scrollSpeed / 30.0 * scrollDirection
            let newY = currentY + step

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
                Configuration.debugLog("Animator: scroll complete, pausing")
            } else {
                layer.position.y = newY
            }
            CATransaction.commit()

        case .fadingIn(let until):
            guard let layer = currentLayer else {
                phase = .idle
                return
            }
            let remaining = until - CACurrentMediaTime()
            if remaining <= 0 {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.opacity = 1
                oldLayer?.removeFromSuperlayer()
                oldLayer = nil
                CATransaction.commit()
                // scrollEndY stores display duration when in fade mode
                let displayDuration = CFTimeInterval(scrollEndY)
                phase = .displaying(until: CACurrentMediaTime() + displayDuration)
            } else {
                let progress = Float(1.0 - remaining / 2.0)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.opacity = max(0, min(1, progress))
                CATransaction.commit()
            }

        case .displaying(let until):
            if CACurrentMediaTime() >= until {
                phase = .idle
                Configuration.debugLog("Animator: display complete")
                onAnimationComplete?()
            }

        case .endPause(let until):
            if CACurrentMediaTime() >= until {
                phase = .idle
                Configuration.debugLog("Animator: end pause complete")
                onAnimationComplete?()
            }
        }
    }

    func stopAnimations() {
        currentLayer?.removeFromSuperlayer()
        oldLayer?.removeFromSuperlayer()
        currentLayer = nil
        oldLayer = nil
        phase = .idle
    }
}
