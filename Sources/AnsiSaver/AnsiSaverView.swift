import ScreenSaver

class AnsiSaverView: ScreenSaverView {

    private var animator: Animator?
    private var artPaths: [String] = []
    private var currentIndex = 0
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 10
    private var config = Configuration.load()
    private var configSheet: ConfigSheet?
    private var messageLayer: CATextLayer?
    private var scopedFolderURL: URL?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 60.0

        if let layer = self.layer {
            animator = Animator(containerLayer: layer)
            animator?.onAnimationComplete = { [weak self] in
                self?.showNextArt()
            }
        }

        Configuration.debugLog("AnsiSaverView.init process=\(ProcessInfo.processInfo.processName) isPreview=\(isPreview)")
        loadArt()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadArt() {
        var sources: [ArtSource] = []

        if let bookmark = config.localFolderBookmark,
           let resolved = Configuration.resolveBookmark(bookmark) {
            scopedFolderURL = resolved.url
            let folderPath = resolved.path

            if isPreview {
                if !folderPath.isEmpty {
                    sources.append(FolderSource(folderPath: folderPath))
                }
            } else {
                for packURL in config.packURLs where !packURL.isEmpty {
                    sources.append(PackSource(packURL: packURL))
                }

                if !config.fileURLs.isEmpty {
                    sources.append(URLSource(fileURLs: config.fileURLs.filter { !$0.isEmpty }))
                }

                if !folderPath.isEmpty {
                    sources.append(FolderSource(folderPath: folderPath))
                }
            }
        } else if !isPreview {
            for packURL in config.packURLs where !packURL.isEmpty {
                sources.append(PackSource(packURL: packURL))
            }

            if !config.fileURLs.isEmpty {
                sources.append(URLSource(fileURLs: config.fileURLs.filter { !$0.isEmpty }))
            }
        }

        guard !sources.isEmpty else {
            showMessage("No art sources configured.\nOpen Screen Saver Options to add pack URLs or a local folder.")
            return
        }

        let group = DispatchGroup()
        var allPaths: [String] = []

        for source in sources {
            group.enter()
            source.loadArtPaths { paths in
                DispatchQueue.main.async {
                    allPaths.append(contentsOf: paths)
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if allPaths.isEmpty {
                self.showMessage("No art files found.\nCheck your configured sources.")
                return
            }
            self.messageLayer?.removeFromSuperlayer()
            self.messageLayer = nil
            self.artPaths = allPaths.shuffled()
            Configuration.debugLog("loadArt: found \(allPaths.count) files, first: \(allPaths.first ?? "none")")

            if self.config.isModemMode {
                self.startModemMode()
            } else if self.config.continuousScroll {
                self.startContinuousMode()
            } else {
                self.showNextArt()
            }
        }
    }

    private func showNextArt() {
        guard !artPaths.isEmpty else { return }
        guard bounds.size.width > 0, bounds.size.height > 0 else { return }

        let path = nextArtPath()
        let transition = TransitionMode(rawValue: config.transitionMode) ?? .scrollUp

        let useModem = self.config.isModemMode

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let sf: UInt8 = self.config.scaleFactor <= 1 ? 0 : UInt8(self.config.scaleFactor)

            let renderResult: RenderResult?
            let image: NSImage?
            if useModem {
                renderResult = Renderer.renderWithInfo(ansFileAt: path, scaleFactor: sf)
                image = renderResult?.image
            } else {
                renderResult = nil
                image = Renderer.render(ansFileAt: path, scaleFactor: sf)
            }

            guard let image = image else {
                DispatchQueue.main.async {
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures < self.maxConsecutiveFailures {
                        self.showNextArt()
                    } else {
                        self.showMessage("Unable to render art files.")
                    }
                }
                return
            }

            // For modem mode, compute content columns per row on background thread
            let modemInfo: (columns: Int, rows: Int, contentCols: [Int])?
            if useModem, let result = renderResult {
                let effectiveScale = max(Int(sf), 1)
                let columns = result.pixelWidth / (8 * effectiveScale)
                let rows = result.pixelHeight / (16 * effectiveScale)
                let contentCols = Renderer.contentColumnsPerRow(for: result, columns: columns, rows: rows)
                modemInfo = (columns, rows, contentCols)
            } else {
                modemInfo = nil
            }

            DispatchQueue.main.async {
                self.consecutiveFailures = 0
                if useModem, let info = modemInfo {
                    self.animator?.appendModemArt(
                        image: image,
                        columns: info.columns,
                        rows: info.rows,
                        contentColumnsPerRow: info.contentCols
                    )
                } else if self.config.continuousScroll {
                    let fileName = (path as NSString).lastPathComponent
                    self.animator?.appendArt(image: image, fileName: fileName, showSeparator: self.config.showSeparator)
                } else {
                    self.animator?.display(
                        image: image,
                        transition: transition,
                        speed: self.config.scrollSpeed,
                        viewSize: self.bounds.size
                    )
                }
            }
        }
    }

    private func startContinuousMode() {
        guard !artPaths.isEmpty else { return }
        guard bounds.size.width > 0, bounds.size.height > 0 else { return }

        let path = nextArtPath()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let image = Renderer.render(ansFileAt: path, scaleFactor: self.config.scaleFactor <= 1 ? 0 : UInt8(self.config.scaleFactor)) else {
                DispatchQueue.main.async {
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures < self.maxConsecutiveFailures {
                        self.startContinuousMode()
                    } else {
                        self.showMessage("Unable to render art files.")
                    }
                }
                return
            }

            DispatchQueue.main.async {
                self.consecutiveFailures = 0
                let fileName = (path as NSString).lastPathComponent
                self.animator?.startContinuousScroll(
                    firstImage: image,
                    fileName: fileName,
                    speed: self.config.scrollSpeed,
                    viewSize: self.bounds.size,
                    showSeparator: self.config.showSeparator
                )
            }
        }
    }

    private func startModemMode() {
        guard !artPaths.isEmpty else { return }
        guard bounds.size.width > 0, bounds.size.height > 0 else { return }

        let path = nextArtPath()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let sf: UInt8 = self.config.scaleFactor <= 1 ? 0 : UInt8(self.config.scaleFactor)
            guard let result = Renderer.renderWithInfo(ansFileAt: path, scaleFactor: sf) else {
                DispatchQueue.main.async {
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures < self.maxConsecutiveFailures {
                        self.startModemMode()
                    } else {
                        self.showMessage("Unable to render art files.")
                    }
                }
                return
            }

            let effectiveScale = max(Int(sf), 1)
            let columns = result.pixelWidth / (8 * effectiveScale)
            let rows = result.pixelHeight / (16 * effectiveScale)
            let contentCols = Renderer.contentColumnsPerRow(for: result, columns: columns, rows: rows)

            DispatchQueue.main.async {
                self.consecutiveFailures = 0
                self.animator?.startModemContinuous(
                    firstImage: result.image,
                    columns: columns,
                    rows: rows,
                    contentColumnsPerRow: contentCols,
                    modemSpeed: self.config.modemSpeed,
                    viewSize: self.bounds.size
                )
            }
        }
    }

    private func nextArtPath() -> String {
        if currentIndex >= artPaths.count {
            artPaths.shuffle()
            currentIndex = 0
        }
        let path = artPaths[currentIndex]
        currentIndex += 1
        return path
    }

    private func showMessage(_ text: String) {
        guard let layer = self.layer else { return }

        messageLayer?.removeFromSuperlayer()

        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = NSFont.systemFont(ofSize: 14) as CTFont
        textLayer.fontSize = isPreview ? 8 : 14
        textLayer.foregroundColor = NSColor.gray.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        textLayer.frame = layer.bounds
        textLayer.isWrapped = true

        layer.addSublayer(textLayer)
        messageLayer = textLayer
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    override func animateOneFrame() {
        animator?.tick()
    }

    override func stopAnimation() {
        super.stopAnimation()
        animator?.stopAnimations()
        scopedFolderURL?.stopAccessingSecurityScopedResource()
        scopedFolderURL = nil
    }

    override var hasConfigureSheet: Bool {
        return true
    }

    override var configureSheet: NSWindow? {
        if configSheet == nil {
            configSheet = ConfigSheet(config: Configuration.load())
        } else {
            configSheet?.reload(Configuration.load())
        }
        return configSheet?.configWindow
    }
}
