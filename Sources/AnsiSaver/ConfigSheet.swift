import AppKit

class ConfigSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private var window: NSWindow!
    private var config: Configuration

    private var packURLs: [String] = []
    private var folderBookmark: Data?

    private var packTable: NSTableView!
    private var folderPathControl: NSPathControl!
    private var displayModePopup: NSPopUpButton!
    private var transitionPopup: NSPopUpButton!
    private var speedSlider: NSSlider!
    private var speedValueLabel: NSTextField!
    private var scalePopup: NSPopUpButton!
    private var continuousCheck: NSButton!
    private var separatorCheck: NSButton!
    private var modemPopup: NSPopUpButton!

    private var modernViews: [NSView] = []
    private var modemViews: [NSView] = []

    init(config: Configuration) {
        self.config = config
        self.packURLs = config.packURLs
        self.folderBookmark = config.localFolderBookmark
        super.init()
        buildWindow()
    }

    var configWindow: NSWindow { window }

    func reload(_ newConfig: Configuration) {
        config = newConfig
        packURLs = newConfig.packURLs
        folderBookmark = newConfig.localFolderBookmark
        packTable.reloadData()
        if let path = newConfig.localFolderPath {
            folderPathControl.url = URL(fileURLWithPath: path)
        } else {
            folderPathControl.url = nil
        }
        displayModePopup.selectItem(at: newConfig.displayMode.rawValue)
        transitionPopup.selectItem(at: newConfig.transitionMode)
        speedSlider.doubleValue = newConfig.scrollSpeed
        speedValueLabel.stringValue = "\(Int(newConfig.scrollSpeed)) px/s"
        scalePopup.selectItem(at: max(newConfig.scaleFactor - 1, 0))
        continuousCheck.state = newConfig.continuousScroll ? .on : .off
        separatorCheck.state = newConfig.showSeparator ? .on : .off
        separatorCheck.isEnabled = newConfig.continuousScroll
        let modemIndex = ModemSpeed.allCases.firstIndex(of: newConfig.modemSpeed) ?? 2
        modemPopup.selectItem(at: modemIndex)
        updateDisplayMode()
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.title = "AnsiSaver Settings"

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        modernViews = []
        modemViews = []

        var y: CGFloat = 480

        // Pack URLs section
        y = addLabel("16colo.rs Pack URLs:", to: contentView, y: y)
        y = addTableSection(table: &packTable, tag: 0, to: contentView, y: y)
        y = addAddRemoveButtons(addAction: #selector(addPackURL), removeAction: #selector(removePackURL),
                                to: contentView, y: y)

        y -= 10

        // Local folder
        y = addLabel("Local Folder:", to: contentView, y: y)
        folderPathControl = NSPathControl(frame: NSRect(x: 20, y: y - 26, width: 380, height: 24))
        folderPathControl.pathStyle = .standard
        folderPathControl.isEditable = false
        if let path = config.localFolderPath {
            folderPathControl.url = URL(fileURLWithPath: path)
        }
        contentView.addSubview(folderPathControl)

        let browseButton = NSButton(title: "Browse...", target: self, action: #selector(browseFolder))
        browseButton.frame = NSRect(x: 410, y: y - 28, width: 90, height: 28)
        contentView.addSubview(browseButton)
        y -= 40

        // Render scale (applies to both modes)
        y = addLabel("Render Scale:", to: contentView, y: y)
        scalePopup = NSPopUpButton(frame: NSRect(x: 120, y: y + 2, width: 180, height: 24))
        scalePopup.addItems(withTitles: ["1x", "2x", "3x", "4x"])
        scalePopup.selectItem(at: max(config.scaleFactor - 1, 0))
        contentView.addSubview(scalePopup)
        y -= 14

        // Display mode toggle
        y = addLabel("Display Mode:", to: contentView, y: y)
        displayModePopup = NSPopUpButton(frame: NSRect(x: 120, y: y + 2, width: 180, height: 24))
        displayModePopup.addItems(withTitles: ["Modern", "Modem"])
        displayModePopup.selectItem(at: config.displayMode.rawValue)
        displayModePopup.target = self
        displayModePopup.action = #selector(displayModeChanged)
        contentView.addSubview(displayModePopup)
        y -= 14

        // ---- Mode-specific controls occupy the same vertical region ----
        let modeStartY = y

        // Modern controls
        do {
            var my = modeStartY

            let transLabel = makeFieldLabel("Transition:", at: my, in: contentView)
            modernViews.append(transLabel)
            my -= 22

            transitionPopup = NSPopUpButton(frame: NSRect(x: 120, y: my + 2, width: 180, height: 24))
            transitionPopup.addItems(withTitles: ["Scroll Up", "Scroll Down", "Crossfade"])
            transitionPopup.selectItem(at: config.transitionMode)
            contentView.addSubview(transitionPopup)
            modernViews.append(transitionPopup)
            my -= 14

            let speedLabel = makeFieldLabel("Scroll Speed:", at: my, in: contentView)
            modernViews.append(speedLabel)
            my -= 22

            speedSlider = NSSlider(frame: NSRect(x: 120, y: my + 4, width: 280, height: 20))
            speedSlider.minValue = 10
            speedSlider.maxValue = 200
            speedSlider.doubleValue = config.scrollSpeed
            speedSlider.target = self
            speedSlider.action = #selector(speedChanged)
            contentView.addSubview(speedSlider)
            modernViews.append(speedSlider)

            speedValueLabel = NSTextField(labelWithString: "\(Int(config.scrollSpeed)) px/s")
            speedValueLabel.frame = NSRect(x: 410, y: my + 2, width: 80, height: 20)
            contentView.addSubview(speedValueLabel)
            modernViews.append(speedValueLabel)
            my -= 20

            continuousCheck = NSButton(checkboxWithTitle: "Continuous scroll", target: self, action: #selector(continuousChanged))
            continuousCheck.frame = NSRect(x: 20, y: my - 20, width: 200, height: 18)
            continuousCheck.state = config.continuousScroll ? .on : .off
            contentView.addSubview(continuousCheck)
            modernViews.append(continuousCheck)
            my -= 24

            separatorCheck = NSButton(checkboxWithTitle: "Show separator between files", target: nil, action: nil)
            separatorCheck.frame = NSRect(x: 40, y: my - 20, width: 240, height: 18)
            separatorCheck.state = config.showSeparator ? .on : .off
            separatorCheck.isEnabled = config.continuousScroll
            contentView.addSubview(separatorCheck)
            modernViews.append(separatorCheck)
            my -= 28

            // Use the bottom of the modern section as the continuation point
            y = my
        }

        // Modem controls (placed at same start position)
        do {
            var my = modeStartY

            let baudLabel = makeFieldLabel("Baud Rate:", at: my, in: contentView)
            modemViews.append(baudLabel)
            my -= 22

            modemPopup = NSPopUpButton(frame: NSRect(x: 120, y: my + 2, width: 180, height: 24))
            modemPopup.addItems(withTitles: ModemSpeed.allCases.map { $0.label })
            let modemIndex = ModemSpeed.allCases.firstIndex(of: config.modemSpeed) ?? 2
            modemPopup.selectItem(at: modemIndex)
            contentView.addSubview(modemPopup)
            modemViews.append(modemPopup)
        }

        updateDisplayMode()

        // ---- End mode-specific region ----

        // Refetch button
        let refetchButton = NSButton(title: "Refetch Packs", target: self, action: #selector(refetchPacks))
        refetchButton.frame = NSRect(x: 20, y: y - 30, width: 120, height: 28)
        contentView.addSubview(refetchButton)

        // OK / Cancel
        let okButton = NSButton(title: "OK", target: self, action: #selector(okPressed))
        okButton.frame = NSRect(x: 410, y: 10, width: 90, height: 28)
        okButton.keyEquivalent = "\r"
        contentView.addSubview(okButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancelButton.frame = NSRect(x: 310, y: 10, width: 90, height: 28)
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)
    }

    private func makeFieldLabel(_ text: String, at y: CGFloat, in view: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        label.frame = NSRect(x: 20, y: y - 18, width: 100, height: 18)
        view.addSubview(label)
        return label
    }

    @discardableResult
    private func addLabel(_ text: String, to view: NSView, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        label.frame = NSRect(x: 20, y: y - 18, width: 480, height: 18)
        view.addSubview(label)
        return y - 22
    }

    private func addTableSection(table: inout NSTableView!, tag: Int, to view: NSView, y: CGFloat) -> CGFloat {
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: y - 100, width: 480, height: 96))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        table = NSTableView(frame: scrollView.bounds)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        column.title = "URL"
        column.isEditable = true
        column.width = 460
        table.addTableColumn(column)
        table.headerView = nil
        table.tag = tag
        table.dataSource = self
        table.delegate = self

        scrollView.documentView = table
        view.addSubview(scrollView)

        return y - 104
    }

    private func addAddRemoveButtons(addAction: Selector, removeAction: Selector,
                                     to view: NSView, y: CGFloat) -> CGFloat {
        let addButton = NSButton(title: "+", target: self, action: addAction)
        addButton.frame = NSRect(x: 20, y: y - 26, width: 30, height: 24)
        addButton.bezelStyle = .smallSquare
        view.addSubview(addButton)

        let removeButton = NSButton(title: "−", target: self, action: removeAction)
        removeButton.frame = NSRect(x: 50, y: y - 26, width: 30, height: 24)
        removeButton.bezelStyle = .smallSquare
        view.addSubview(removeButton)

        return y - 30
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return packURLs.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return packURLs[row]
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let value = object as? String else { return }
        packURLs[row] = value
    }

    // MARK: - Actions

    @objc private func addPackURL() {
        packURLs.append("https://16colo.rs/pack/")
        packTable.reloadData()
        packTable.editColumn(0, row: packURLs.count - 1, with: nil, select: true)
    }

    @objc private func removePackURL() {
        let row = packTable.selectedRow
        guard row >= 0 else { return }
        packURLs.remove(at: row)
        packTable.reloadData()
    }

    @objc private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.folderPathControl.url = url
                self?.folderBookmark = Configuration.createBookmark(for: url)
            }
        }
    }

    @objc private func speedChanged() {
        speedValueLabel.stringValue = "\(Int(speedSlider.doubleValue)) px/s"
    }

    @objc private func continuousChanged() {
        separatorCheck.isEnabled = continuousCheck.state == .on
    }

    @objc private func displayModeChanged() {
        updateDisplayMode()
    }

    private func updateDisplayMode() {
        let isModem = DisplayMode(rawValue: displayModePopup.indexOfSelectedItem) == .modem
        for view in modernViews { view.isHidden = isModem }
        for view in modemViews { view.isHidden = !isModem }
    }

    @objc private func refetchPacks() {
        Cache.clearPacks()
        let alert = NSAlert()
        alert.messageText = "Pack cache cleared"
        alert.informativeText = "Packs will be re-downloaded when the screensaver next activates."
        alert.runModal()
    }

    @objc private func okPressed() {
        config.packURLs = packURLs.filter { !$0.isEmpty }
        config.localFolderBookmark = folderBookmark
        config.transitionMode = transitionPopup.indexOfSelectedItem
        config.scrollSpeed = speedSlider.doubleValue
        config.scaleFactor = scalePopup.indexOfSelectedItem + 1
        config.continuousScroll = continuousCheck.state == .on
        config.showSeparator = separatorCheck.state == .on
        config.displayMode = DisplayMode(rawValue: displayModePopup.indexOfSelectedItem) ?? .modern
        let modemIdx = modemPopup.indexOfSelectedItem
        config.modemSpeed = (modemIdx >= 0 && modemIdx < ModemSpeed.allCases.count)
            ? ModemSpeed.allCases[modemIdx]
            : .baud2400
        config.save()

        dismissSheet()
    }

    @objc private func cancelPressed() {
        dismissSheet()
    }

    private func dismissSheet() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
}
