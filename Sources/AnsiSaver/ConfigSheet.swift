import AppKit

class ConfigSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private var window: NSWindow!
    private var config: Configuration

    private var packURLs: [String] = []
    private var folderBookmark: Data?

    private var packTable: NSTableView!
    private var folderPathControl: NSPathControl!
    private var transitionPopup: NSPopUpButton!
    private var speedSlider: NSSlider!
    private var speedLabel: NSTextField!
    private var scalePopup: NSPopUpButton!
    private var continuousCheck: NSButton!
    private var separatorCheck: NSButton!

    init(config: Configuration) {
        self.config = config
        self.packURLs = config.packURLs
        self.folderBookmark = config.localFolderBookmark
        super.init()
        buildWindow()
    }

    var configWindow: NSWindow { window }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.title = "AnsiSaver Settings"

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        var y: CGFloat = 440

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

        // Transition mode
        y = addLabel("Transition:", to: contentView, y: y)
        transitionPopup = NSPopUpButton(frame: NSRect(x: 120, y: y + 2, width: 180, height: 24))
        transitionPopup.addItems(withTitles: ["Scroll Up", "Scroll Down", "Crossfade"])
        transitionPopup.selectItem(at: config.transitionMode)
        contentView.addSubview(transitionPopup)
        y -= 14

        // Speed slider
        y = addLabel("Scroll Speed:", to: contentView, y: y)
        speedSlider = NSSlider(frame: NSRect(x: 120, y: y + 4, width: 280, height: 20))
        speedSlider.minValue = 10
        speedSlider.maxValue = 200
        speedSlider.doubleValue = config.scrollSpeed
        speedSlider.target = self
        speedSlider.action = #selector(speedChanged)
        contentView.addSubview(speedSlider)

        speedLabel = NSTextField(labelWithString: "\(Int(config.scrollSpeed)) px/s")
        speedLabel.frame = NSRect(x: 410, y: y + 2, width: 80, height: 20)
        contentView.addSubview(speedLabel)
        y -= 20

        // Scale factor
        y = addLabel("Render Scale:", to: contentView, y: y)
        scalePopup = NSPopUpButton(frame: NSRect(x: 120, y: y + 2, width: 180, height: 24))
        scalePopup.addItems(withTitles: ["1x", "2x", "3x", "4x"])
        scalePopup.selectItem(at: config.scaleFactor - 1)
        contentView.addSubview(scalePopup)
        y -= 14

        // Continuous scroll
        continuousCheck = NSButton(checkboxWithTitle: "Continuous scroll", target: self, action: #selector(continuousChanged))
        continuousCheck.frame = NSRect(x: 20, y: y - 20, width: 200, height: 18)
        continuousCheck.state = config.continuousScroll ? .on : .off
        contentView.addSubview(continuousCheck)
        y -= 24

        separatorCheck = NSButton(checkboxWithTitle: "Show separator between files", target: nil, action: nil)
        separatorCheck.frame = NSRect(x: 40, y: y - 20, width: 240, height: 18)
        separatorCheck.state = config.showSeparator ? .on : .off
        separatorCheck.isEnabled = config.continuousScroll
        contentView.addSubview(separatorCheck)
        y -= 28

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
        speedLabel.stringValue = "\(Int(speedSlider.doubleValue)) px/s"
    }

    @objc private func continuousChanged() {
        separatorCheck.isEnabled = continuousCheck.state == .on
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
        config.save()

        window.sheetParent?.endSheet(window)
    }

    @objc private func cancelPressed() {
        window.sheetParent?.endSheet(window)
    }
}
