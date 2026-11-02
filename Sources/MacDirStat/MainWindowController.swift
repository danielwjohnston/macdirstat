import Cocoa
import Quartz

public final class ExtensionSummary: NSObject, @unchecked Sendable {
    public let ext: String
    public let bytes: UInt64
    public let fileCount: Int
    public let color: NSColor
    
    public init(ext: String, bytes: UInt64, fileCount: Int, color: NSColor) {
        self.ext = ext
        self.bytes = bytes
        self.fileCount = fileCount
        self.color = color
    }
    
    /// ".swift" for real extensions; pseudo names such as <none>, <dir> and app/pkg are shown as-is
    public static func displayName(for ext: String) -> String {
        return ext.hasPrefix("<") || ext.contains("/") ? ext : "." + ext
    }
}

@MainActor
public final class MainWindowController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, TreeMapSelectionDelegate, SelectDrivesDelegate, @MainActor QLPreviewPanelDataSource {
    
    private var globalRootItem: FileItem?
    private var currentZoomRoot: FileItem?
    private var selectedItem: FileItem?
    private var extensionSummaries: [ExtensionSummary] = []
    
    private var splitView: NSSplitView!
    private var topSplit: NSSplitView!
    private var outlineView: NSOutlineView!
    private var extTableView: NSTableView!
    private var treeMapView: TreeMapView!
    private var statusLabel: NSTextField!
    private var pacmanLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    private var zoomUpButton: NSButton!
    private var packageToggleCheckbox: NSButton!
    private var palettePopUp: NSPopUpButton!
    private var headerBar: NSView!
    private var statusBar: NSView!
    
    private var currentScanURLs: [URL] = []
    private var scanSession: ScanSession?
    private var extensionTotals: [String: ExtensionStat] = [:]
    private var pacmanTimer: Timer?
    private var renderTimer: Timer?
    private var pacmanFrame = 0
    private let pacmanAnim = ["ᗧ • • • •", "ᗧ• • • • ", "ᗧ  • • • ", "ᗧ   • • ", "ᗧ    • ", "ᗧ     ", "ᗤ     ", "ᗤ    •", "ᗤ   • •", "ᗤ  • • •"]
    
    private var isScanning = false
    
    private var selectDrivesController: SelectDrivesWindowController?
    private var preferencesController: PreferencesWindowController?
    
    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1220, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacDirStat — Native AppKit (WinDirStat 1:1 Parity)"
        self.init(window: window)
        setupUI()
        applyTheme()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: NSNotification.Name("ThemeChangedNotification"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTreemapSettingsChanged),
            name: AppSettings.treemapSettingsChangedNotification,
            object: nil
        )
        
        // Listen to macOS light/dark system appearance changes dynamically
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        let container = NSView(frame: window.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        window.contentView = container
        
        // 1. Toolbar / Header Bar (Height 52)
        headerBar = NSView(frame: NSRect(x: 0, y: container.bounds.height - 52, width: container.bounds.width, height: 52))
        headerBar.autoresizingMask = [.width, .minYMargin]
        headerBar.wantsLayer = true
        container.addSubview(headerBar)
        
        let selectDrivesBtn = NSButton(title: "Select Drives...", target: self, action: #selector(openSelectDrives))
        selectDrivesBtn.bezelStyle = .rounded
        selectDrivesBtn.frame = NSRect(x: 14, y: 12, width: 130, height: 28)
        headerBar.addSubview(selectDrivesBtn)
        
        zoomUpButton = NSButton(title: "⇪ Zoom Out", target: self, action: #selector(zoomOut))
        zoomUpButton.bezelStyle = .rounded
        zoomUpButton.frame = NSRect(x: 152, y: 12, width: 100, height: 28)
        zoomUpButton.isEnabled = false
        headerBar.addSubview(zoomUpButton)
        
        packageToggleCheckbox = NSButton(checkboxWithTitle: "Inspect Packages", target: self, action: #selector(togglePackageInspection))
        packageToggleCheckbox.frame = NSRect(x: 260, y: 16, width: 135, height: 20)
        packageToggleCheckbox.state = .off
        headerBar.addSubview(packageToggleCheckbox)
        
        palettePopUp = NSPopUpButton(frame: NSRect(x: 405, y: 12, width: 160, height: 28), pullsDown: false)
        for mode in ColorPaletteMode.allCases {
            palettePopUp.addItem(withTitle: mode.rawValue)
        }
        palettePopUp.target = self
        palettePopUp.action = #selector(paletteModeChanged)
        headerBar.addSubview(palettePopUp)
        
        let settingsBtn = NSButton(title: "⚙ Preferences", target: self, action: #selector(openPreferences))
        settingsBtn.bezelStyle = .rounded
        settingsBtn.frame = NSRect(x: 575, y: 12, width: 115, height: 28)
        headerBar.addSubview(settingsBtn)
        
        let exportBtn = NSButton(title: "Export CSV", target: self, action: #selector(exportToCSV))
        exportBtn.bezelStyle = .rounded
        exportBtn.frame = NSRect(x: 698, y: 12, width: 100, height: 28)
        headerBar.addSubview(exportBtn)
        
        progressIndicator = NSProgressIndicator(frame: NSRect(x: 810, y: 16, width: 20, height: 20))
        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        headerBar.addSubview(progressIndicator)
        
        pacmanLabel = NSTextField(labelWithString: "")
        pacmanLabel.frame = NSRect(x: 840, y: 15, width: 150, height: 20)
        pacmanLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        pacmanLabel.textColor = NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.15, alpha: 1.0)
        headerBar.addSubview(pacmanLabel)
        
        // 2. Status Bar at Bottom
        statusBar = NSView(frame: NSRect(x: 0, y: 0, width: container.bounds.width, height: 28))
        statusBar.autoresizingMask = [.width, .maxYMargin]
        statusBar.wantsLayer = true
        container.addSubview(statusBar)
        
        let divider = NSBox(frame: NSRect(x: 0, y: 27, width: statusBar.bounds.width, height: 1))
        divider.autoresizingMask = [.width]
        divider.boxType = .separator
        statusBar.addSubview(divider)
        
        statusLabel = NSTextField(labelWithString: "Ready. Click 'Select Drives...' to start scanning.")
        statusLabel.frame = NSRect(x: 14, y: 5, width: statusBar.bounds.width - 28, height: 18)
        statusLabel.autoresizingMask = [.width]
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusBar.addSubview(statusLabel)
        
        // 3. Main Split View between Top Lists and Bottom Treemap
        splitView = NSSplitView(frame: NSRect(x: 0, y: 28, width: container.bounds.width, height: container.bounds.height - 80))
        splitView.autoresizingMask = [.width, .height]
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        container.addSubview(splitView)
        
        // Top Split: Outline View (60%) | Extension Table View (40%)
        topSplit = NSSplitView(frame: NSRect(x: 0, y: 0, width: splitView.bounds.width, height: splitView.bounds.height * 0.52))
        topSplit.isVertical = true
        topSplit.dividerStyle = .thin
        
        // 3A. File Hierarchy Outline View
        let outlineScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: topSplit.bounds.width * 0.60, height: topSplit.bounds.height))
        outlineScroll.hasVerticalScroller = true
        outlineScroll.hasHorizontalScroller = true
        outlineScroll.autohidesScrollers = true
        
        outlineView = NSOutlineView(frame: outlineScroll.bounds)
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowHeight = 22
        outlineView.intercellSpacing = NSSize(width: 8, height: 2)
        
        let colName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        colName.title = "Name"
        colName.width = 300
        outlineView.addTableColumn(colName)
        
        let colSubtree = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Subtree"))
        colSubtree.title = "Subtree %"
        colSubtree.width = 110
        outlineView.addTableColumn(colSubtree)
        
        let colSize = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
        colSize.title = "Size"
        colSize.width = 95
        outlineView.addTableColumn(colSize)
        
        let colItems = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Items"))
        colItems.title = "Items"
        colItems.width = 65
        outlineView.addTableColumn(colItems)
        
        let colFiles = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Files"))
        colFiles.title = "Files"
        colFiles.width = 65
        outlineView.addTableColumn(colFiles)
        
        let colDirs = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Dirs"))
        colDirs.title = "Dirs"
        colDirs.width = 55
        outlineView.addTableColumn(colDirs)
        
        outlineView.outlineTableColumn = colName
        outlineScroll.documentView = outlineView
        topSplit.addSubview(outlineScroll)
        
        // 3B. Extension Summary Table View
        let tableScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: topSplit.bounds.width * 0.40, height: topSplit.bounds.height))
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = false
        tableScroll.autohidesScrollers = true
        
        extTableView = NSTableView(frame: tableScroll.bounds)
        extTableView.dataSource = self
        extTableView.delegate = self
        extTableView.rowHeight = 22
        extTableView.intercellSpacing = NSSize(width: 8, height: 2)
        
        let colExt = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Ext"))
        colExt.title = "Extension"
        colExt.width = 110
        extTableView.addTableColumn(colExt)
        
        let colExtBytes = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ExtBytes"))
        colExtBytes.title = "Total Size"
        colExtBytes.width = 95
        extTableView.addTableColumn(colExtBytes)
        
        let colExtGraph = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ExtGraph"))
        colExtGraph.title = "% Bytes"
        colExtGraph.width = 95
        extTableView.addTableColumn(colExtGraph)
        
        let colExtCount = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ExtCount"))
        colExtCount.title = "Files"
        colExtCount.width = 60
        extTableView.addTableColumn(colExtCount)
        
        tableScroll.documentView = extTableView
        topSplit.addSubview(tableScroll)
        
        splitView.addSubview(topSplit)
        
        // 3C. Cushion Treemap View
        treeMapView = TreeMapView(frame: NSRect(x: 0, y: 0, width: splitView.bounds.width, height: splitView.bounds.height * 0.48))
        treeMapView.delegate = self
        splitView.addSubview(treeMapView)
        
        topSplit.adjustSubviews()
        splitView.adjustSubviews()
    }
    
    @objc private func handleTreemapSettingsChanged() {
        treeMapView.refresh()
    }
    
    @objc private func handleThemeChanged() {
        applyTheme()
        ExtensionColorManager.shared.resetPalette()
        refreshExtensionTable()
        outlineView.reloadData()
        treeMapView.refresh()
    }
    
    private func applyTheme() {
        let theme = AppSettings.shared.theme
        window?.backgroundColor = theme.windowBackgroundColor
        headerBar.layer?.backgroundColor = theme.windowBackgroundColor.cgColor
        statusBar.layer?.backgroundColor = theme.windowBackgroundColor.cgColor
        statusLabel.textColor = theme.secondaryTextColor
        
        outlineView.backgroundColor = theme.controlBackgroundColor
        extTableView.backgroundColor = theme.controlBackgroundColor
        
        if theme.isClassicWin32 {
            splitView.dividerStyle = .thick
            topSplit.dividerStyle = .thick
        } else {
            splitView.dividerStyle = .thin
            topSplit.dividerStyle = .thin
        }
    }
    
    // MARK: - Actions
    @objc private func openSelectDrives() {
        if selectDrivesController == nil {
            selectDrivesController = SelectDrivesWindowController()
            selectDrivesController?.delegate = self
        }
        selectDrivesController?.showWindow(nil)
        selectDrivesController?.window?.center()
        selectDrivesController?.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.showWindow(nil)
        preferencesController?.window?.center()
        preferencesController?.window?.makeKeyAndOrderFront(nil)
    }
    
    public func didSelectScanTarget(urls: [URL]) {
        startScan(urls: urls)
    }
    
    @objc private func togglePackageInspection() {
        rescan()
    }
    
    @objc public func rescan() {
        if !currentScanURLs.isEmpty {
            startScan(urls: currentScanURLs)
        }
    }
    
    @objc public func showSelectDrives() {
        openSelectDrives()
    }
    
    @objc public func showPreferences() {
        openPreferences()
    }
    
    @objc private func paletteModeChanged() {
        if let selectedTitle = palettePopUp.titleOfSelectedItem,
           let mode = ColorPaletteMode(rawValue: selectedTitle) {
            treeMapView.paletteMode = mode
        }
    }
    
    @objc private func zoomOut() {
        guard let current = currentZoomRoot, let parent = current.parent else {
            currentZoomRoot = globalRootItem
            zoomUpButton.isEnabled = false
            treeMapView.displayedRootItem = globalRootItem
            return
        }
        currentZoomRoot = parent
        treeMapView.displayedRootItem = parent
        zoomUpButton.isEnabled = (parent !== globalRootItem)
        statusLabel.stringValue = "Zoomed to: \(parent.url.path)"
    }
    
    @objc public func exportReport() {
        exportToCSV()
    }
    
    @objc public func zoomOutAction() {
        if zoomUpButton.isEnabled {
            zoomOut()
        }
    }
    
    @objc private func exportToCSV() {
        guard let root = globalRootItem else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "MacDirStat_\(root.name).csv"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            var lines = ["Name,Path,Size (Bytes),Formatted Size,Subtree %,Files,Subdirectories"]
            // RFC 4180: quote every text field and double any embedded quotes
            func csvField(_ value: String) -> String {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            func traverse(item: FileItem) {
                let pct = String(format: "%.2f%%", item.subtreePercentage() * 100)
                lines.append("\(csvField(item.name)),\(csvField(item.url.path)),\(item.size),\(csvField(item.formattedSize())),\(pct),\(item.fileCount),\(item.subdirCount)")
                for child in item.children {
                    traverse(item: child)
                }
            }
            traverse(item: root)
            let csvText = lines.joined(separator: "\n") + "\n"
            do {
                try csvText.write(to: url, atomically: true, encoding: .utf8)
                statusLabel.stringValue = "Exported report to \(url.lastPathComponent)"
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
    
    // Quick Look (Spacebar) Support
    public override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            toggleQuickLook()
        } else {
            super.keyDown(with: event)
        }
    }
    
    @objc public func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else if let item = selectedItem, !item.isSpecialNode {
            panel.makeKeyAndOrderFront(nil)
        }
    }
    
    public override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }
    
    // QLPreviewPanel calls these informal-protocol hooks on the main thread
    public override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.reloadData()
        }
    }
    
    public override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
        }
    }
    
    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        guard let item = selectedItem, !item.isSpecialNode else { return 0 }
        return 1
    }
    
    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return selectedItem?.url as NSURL?
    }
    
    // MARK: - Scanning
    public func startScan(at url: URL) {
        startScan(urls: [url])
    }
    
    public func startScan(urls: [URL]) {
        guard !urls.isEmpty else { return }
        scanSession?.cancel()
        let session = ScanSession()
        scanSession = session
        currentScanURLs = urls
        isScanning = true
        extensionTotals = [:]
        progressIndicator.startAnimation(nil)
        
        // A single target is the root itself; several drives hang under a synthetic root like WinDirStat's "My Computer"
        let root: FileItem
        var targets: [(url: URL, node: FileItem)] = []
        if urls.count == 1, let url = urls.first {
            root = FileItem(name: displayName(for: url), url: url, isDirectory: true)
            targets = [(url, root)]
        } else {
            root = FileItem(name: "Selected Drives", url: URL(fileURLWithPath: "/"), isDirectory: true)
            for url in urls {
                let node = FileItem(name: displayName(for: url), url: url, isDirectory: true)
                root.attach(node)
                targets.append((url, node))
            }
        }
        let scanLabel = urls.count == 1 ? urls[0].path : "\(urls.count) drives"
        statusLabel.stringValue = "Scanning \(scanLabel)..."
        
        self.globalRootItem = root
        self.currentZoomRoot = root
        self.selectedItem = nil
        self.zoomUpButton.isEnabled = false
        self.treeMapView.selectedItem = nil
        self.treeMapView.displayedRootItem = root
        self.treeMapView.needsLayout = true
        self.outlineView.reloadData()
        self.refreshExtensionTable()
        
        // Chomping Pac-Man Animation
        pacmanTimer?.invalidate()
        pacmanFrame = 0
        pacmanTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pacmanFrame = (self.pacmanFrame + 1) % self.pacmanAnim.count
                self.pacmanLabel.stringValue = self.pacmanAnim[self.pacmanFrame]
            }
        }
        
        // Refresh views at 10 FPS during the scan; the tree itself is only mutated on the main thread
        renderTimer?.invalidate()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.isScanning, self.scanSession === session else { return }
                self.treeMapView.needsLayout = true
                self.statusLabel.stringValue = "Scanning: \(session.itemCount) items (\(root.formattedSize()))..."
                self.outlineView.reloadData()
                self.refreshExtensionTable()
            }
        }
        
        let inspectPackages = packageToggleCheckbox.state == .on
        let showFree = AppSettings.shared.showFreeSpace
        let scanOptions = DirectoryScanner.ScanOptions(inspectInsidePackages: inspectPackages, showFreeSpace: showFree)
        let startTime = CFAbsoluteTimeGetCurrent()
        let scanTargets = targets
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            DispatchQueue.concurrentPerform(iterations: scanTargets.count) { index in
                let target = scanTargets[index]
                DirectoryScanner.scan(url: target.url, options: scanOptions, rootItem: target.node, session: session) { item in
                    // Extension stats are computed here, off the main thread, while the subtree is still private
                    let stats = item.extensionStats()
                    DispatchQueue.main.async {
                        guard let self = self, self.scanSession === session else { return }
                        target.node.attach(item)
                        self.mergeExtensionStats(stats, sign: 1)
                    }
                }
            }
            
            DispatchQueue.main.async {
                guard let self = self, self.scanSession === session else { return }
                self.isScanning = false
                self.renderTimer?.invalidate()
                self.renderTimer = nil
                self.pacmanTimer?.invalidate()
                self.pacmanTimer = nil
                self.pacmanLabel.stringValue = "✓ Ready"
                self.progressIndicator.stopAnimation(nil)
                
                self.refreshExtensionTable()
                self.outlineView.reloadData()
                self.outlineView.expandItem(root)
                self.treeMapView.needsLayout = true
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                self.statusLabel.stringValue = "Scan complete: \(root.formattedSize()) across \(session.itemCount) items in \(scanLabel) (\(String(format: "%.1f", elapsed)) s)"
            }
        }
    }
    
    private func displayName(for url: URL) -> String {
        if let volumeName = try? url.resourceValues(forKeys: [.isVolumeKey, .volumeNameKey]),
           volumeName.isVolume == true, let name = volumeName.volumeName {
            return name
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
    
    private func mergeExtensionStats(_ stats: [String: ExtensionStat], sign: Int) {
        for (ext, stat) in stats {
            var total = extensionTotals[ext] ?? ExtensionStat()
            if sign >= 0 {
                total.bytes += stat.bytes
                total.count += stat.count
            } else {
                total.bytes -= min(total.bytes, stat.bytes)
                total.count = max(0, total.count - stat.count)
            }
            extensionTotals[ext] = total.count > 0 || total.bytes > 0 ? total : nil
        }
    }
    
    private func refreshExtensionTable() {
        self.extensionSummaries = extensionTotals
            .sorted(by: { $0.value.bytes > $1.value.bytes })
            .map {
                ExtensionSummary(
                    ext: $0.key,
                    bytes: $0.value.bytes,
                    fileCount: $0.value.count,
                    color: ExtensionColorManager.shared.color(for: $0.key)
                )
            }
        self.extTableView.reloadData()
    }
    
    // MARK: - Context Menu & User Cleanups
    public func showContextMenu(for item: FileItem, at point: NSPoint) {
        let menu = NSMenu()
        
        let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(contextReveal), keyEquivalent: "r")
        revealItem.target = self
        menu.addItem(revealItem)
        
        let copyPathItem = NSMenuItem(title: "Copy Path", action: #selector(contextCopyPath), keyEquivalent: "c")
        copyPathItem.target = self
        menu.addItem(copyPathItem)
        
        menu.addItem(NSMenuItem.separator())
        
        if item.isSpecialNode {
            menu.popUp(positioning: nil, at: point, in: treeMapView)
            return
        }
        
        // Custom Cleanups
        for cleanup in AppSettings.shared.cleanups {
            let cleanItem = NSMenuItem(title: cleanup.title, action: #selector(executeUserCleanup(_:)), keyEquivalent: "")
            cleanItem.representedObject = cleanup
            cleanItem.target = self
            menu.addItem(cleanItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let trashItem = NSMenuItem(title: "Move to Trash", action: #selector(contextTrash), keyEquivalent: "")
        trashItem.target = self
        menu.addItem(trashItem)
        
        trashItem.isEnabled = item.parent != nil && !currentScanURLs.contains(item.url)
        
        menu.popUp(positioning: nil, at: point, in: treeMapView)
    }
    
    @objc private func contextReveal() {
        guard let item = selectedItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
    
    @objc private func contextCopyPath() {
        guard let item = selectedItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
        statusLabel.stringValue = "Copied path: \(item.url.path)"
    }
    
    @objc private func contextTrash() {
        guard let item = selectedItem else { return }
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = "Are you sure you want to move \(item.name) (\(item.formattedSize())) to the Trash?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                // Remove the subtree in place (as WinDirStat does) instead of rescanning the whole target
                mergeExtensionStats(item.extensionStats(), sign: -1)
                let wasZoomedInside = isAncestor(item, of: currentZoomRoot)
                item.detachFromParent()
                if wasZoomedInside {
                    currentZoomRoot = globalRootItem
                    treeMapView.displayedRootItem = globalRootItem
                    zoomUpButton.isEnabled = false
                }
                selectedItem = nil
                treeMapView.selectedItem = nil
                outlineView.reloadData()
                refreshExtensionTable()
                treeMapView.refresh()
                statusLabel.stringValue = "Moved \(item.name) (\(item.formattedSize())) to Trash."
            } catch {
                let errAlert = NSAlert(error: error)
                errAlert.runModal()
            }
        }
    }
    
    private func isAncestor(_ candidate: FileItem, of item: FileItem?) -> Bool {
        var node = item
        while let n = node {
            if n === candidate { return true }
            node = n.parent
        }
        return false
    }
    
    @objc private func executeUserCleanup(_ sender: NSMenuItem) {
        guard let cleanup = sender.representedObject as? UserCleanupCommand,
              let item = selectedItem else { return }
        
        do {
            let process = UserCleanupCommand.makeProcess(template: cleanup.commandTemplate, path: item.url.path, name: item.name, size: item.formattedSize())
            try process.run()
            statusLabel.stringValue = "Executed cleanup: \(cleanup.title)"
        } catch {
            NSAlert(error: error).runModal()
        }
    }
    
    // MARK: - TreeMapSelectionDelegate
    public func didSelect(item: FileItem) {
        self.selectedItem = item
        statusLabel.stringValue = "Selected: \(item.url.path) [\(item.formattedSize())]"
        
        var ancestors: [FileItem] = []
        var curr = item.parent
        while let c = curr {
            ancestors.insert(c, at: 0)
            curr = c.parent
        }
        for anc in ancestors {
            outlineView.expandItem(anc)
        }
        let row = outlineView.row(forItem: item)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }
    
    public func didDoubleClick(item: FileItem) {
        if item.isDirectory && !item.children.isEmpty && item !== currentZoomRoot {
            currentZoomRoot = item
            treeMapView.displayedRootItem = item
            zoomUpButton.isEnabled = (item !== globalRootItem)
            statusLabel.stringValue = "Zoomed to subtree: \(item.url.path)"
        }
    }
    
    // MARK: - NSOutlineViewDataSource
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return globalRootItem != nil ? 1 : 0
        }
        guard let f = item as? FileItem else { return 0 }
        return f.children.count
    }
    
    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return globalRootItem!
        }
        let f = item as! FileItem
        return f.children[index]
    }
    
    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let f = item as? FileItem else { return false }
        return f.isDirectory && !f.children.isEmpty
    }
    
    // MARK: - NSOutlineViewDelegate
    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let f = item as? FileItem, let col = tableColumn else { return nil }
        let identifier = col.identifier
        let theme = AppSettings.shared.theme
        
        if identifier.rawValue == "Subtree" {
            let barCell = PercentBarCellView(frame: NSRect(x: 0, y: 0, width: col.width, height: 22))
            barCell.percentage = f.subtreePercentage()
            barCell.barColor = ExtensionColorManager.shared.color(for: f.extensionName)
            return barCell
        }
        
        let cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: col.width, height: 22))
        cellView.identifier = identifier
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 2, width: col.width, height: 18))
        textField.isBordered = false
        textField.isEditable = false
        textField.drawsBackground = false
        textField.textColor = theme.textColor
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.autoresizingMask = [.width]
        cellView.textField = textField
        cellView.addSubview(textField)
        
        switch identifier.rawValue {
        case "Name":
            let icon = f.isSpecialNode ? "◻ " : (f.isPackage ? "📦 " : (f.isDirectory ? "📁 " : "📄 "))
            textField.stringValue = icon + f.name
            textField.alignment = .left
        case "Size":
            textField.stringValue = f.formattedSize()
            textField.alignment = .right
        case "Items":
            let total = f.fileCount + f.subdirCount
            textField.stringValue = f.isDirectory ? "\(total)" : ""
            textField.alignment = .right
            textField.textColor = theme.secondaryTextColor
        case "Files":
            textField.stringValue = f.isDirectory ? "\(f.fileCount)" : ""
            textField.alignment = .right
            textField.textColor = theme.secondaryTextColor
        case "Dirs":
            textField.stringValue = f.isDirectory ? "\(f.subdirCount)" : ""
            textField.alignment = .right
            textField.textColor = theme.secondaryTextColor
        default:
            break
        }
        return cellView
    }
    
    public func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        if row >= 0, let item = outlineView.item(atRow: row) as? FileItem {
            self.selectedItem = item
            treeMapView.selectedItem = item
            statusLabel.stringValue = "Selected: \(item.url.path) [\(item.formattedSize())]"
        }
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return extensionSummaries.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn, row < extensionSummaries.count else { return nil }
        let summary = extensionSummaries[row]
        let id = col.identifier
        let theme = AppSettings.shared.theme
        let totalScannedBytes = globalRootItem?.size ?? 1
        
        if id.rawValue == "ExtGraph" {
            let barCell = PercentBarCellView(frame: NSRect(x: 0, y: 0, width: col.width, height: 22))
            barCell.percentage = Double(summary.bytes) / Double(max(1, totalScannedBytes))
            barCell.barColor = summary.color
            return barCell
        }
        
        let cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: col.width, height: 22))
        cellView.identifier = id
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 2, width: col.width, height: 18))
        textField.isBordered = false
        textField.isEditable = false
        textField.drawsBackground = false
        textField.textColor = theme.textColor
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.autoresizingMask = [.width]
        cellView.textField = textField
        cellView.addSubview(textField)
        
        switch id.rawValue {
        case "Ext":
            textField.stringValue = "■ " + ExtensionSummary.displayName(for: summary.ext)
            textField.textColor = summary.color
        case "ExtBytes":
            textField.stringValue = ByteCountFormatter.string(fromByteCount: Int64(summary.bytes), countStyle: .file)
            textField.alignment = .right
        case "ExtCount":
            textField.stringValue = "\(summary.fileCount)"
            textField.alignment = .right
            textField.textColor = theme.secondaryTextColor
        default:
            break
        }
        return cellView
    }
    
    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = extTableView.selectedRow
        if row >= 0, row < extensionSummaries.count {
            let summary = extensionSummaries[row]
            statusLabel.stringValue = "Extension: \(ExtensionSummary.displayName(for: summary.ext)) — \(ByteCountFormatter.string(fromByteCount: Int64(summary.bytes), countStyle: .file)) in \(summary.fileCount) files"
        }
    }
}
