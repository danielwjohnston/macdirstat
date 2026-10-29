import Cocoa

public struct VolumeInfo: Identifiable {
    public let id = UUID()
    public let name: String
    public let url: URL
    public let totalCapacity: UInt64
    public let freeCapacity: UInt64
    public let isRemovable: Bool
    public var isSelected: Bool = false
    
    public var usedCapacity: UInt64 {
        return totalCapacity > freeCapacity ? (totalCapacity - freeCapacity) : 0
    }
    
    public var percentUsed: Double {
        guard totalCapacity > 0 else { return 0.0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }
}

@MainActor
public protocol SelectDrivesDelegate: AnyObject {
    func didSelectScanTarget(urls: [URL])
}

@MainActor
public final class SelectDrivesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    
    public weak var delegate: SelectDrivesDelegate?
    private var volumes: [VolumeInfo] = []
    
    private var radioAllDrives: NSButton!
    private var radioIndividualDrives: NSButton!
    private var radioFolder: NSButton!
    
    private var tableView: NSTableView!
    private var folderPathField: NSTextField!
    private var browseButton: NSButton!
    private var okButton: NSButton!
    private var cancelButton: NSButton!
    
    private var chosenFolderURL: URL?
    
    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Select Drives"
        self.init(window: window)
        loadVolumes()
        setupUI()
    }
    
    private func loadVolumes() {
        volumes.removeAll()
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey
        ]
        
        let mounted = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        for vURL in mounted {
            let values = try? vURL.resourceValues(forKeys: Set(keys))
            let name = values?.volumeName ?? vURL.lastPathComponent
            let total = UInt64(values?.volumeTotalCapacity ?? 0)
            let free = UInt64(values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0))
            let isRemovable = values?.volumeIsRemovable ?? false
            if total > 0 {
                var v = VolumeInfo(name: name, url: vURL, totalCapacity: total, freeCapacity: free, isRemovable: isRemovable)
                if vURL.path == "/" {
                    v.isSelected = true
                }
                volumes.append(v)
            }
        }
    }
    
    private func setupUI() {
        guard let window = window else { return }
        let view = NSView(frame: window.contentView!.bounds)
        window.contentView = view
        
        // 1. Radio Group: All Local Drives
        radioAllDrives = NSButton(radioButtonWithTitle: "All Local Drives", target: self, action: #selector(radioChanged))
        radioAllDrives.frame = NSRect(x: 20, y: 375, width: 200, height: 22)
        view.addSubview(radioAllDrives)
        
        // 2. Radio Group: Individual Drives
        radioIndividualDrives = NSButton(radioButtonWithTitle: "Individual Drives", target: self, action: #selector(radioChanged))
        radioIndividualDrives.frame = NSRect(x: 20, y: 345, width: 200, height: 22)
        radioIndividualDrives.state = .on
        view.addSubview(radioIndividualDrives)
        
        // Table of Drives
        let scroll = NSScrollView(frame: NSRect(x: 40, y: 155, width: 480, height: 180))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        
        tableView = NSTableView(frame: scroll.bounds)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        
        let colCheck = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Check"))
        colCheck.title = ""
        colCheck.width = 28
        tableView.addTableColumn(colCheck)
        
        let colName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        colName.title = "Drive / Volume"
        colName.width = 170
        tableView.addTableColumn(colName)
        
        let colTotal = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Total"))
        colTotal.title = "Total Size"
        colTotal.width = 90
        tableView.addTableColumn(colTotal)
        
        let colFree = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Free"))
        colFree.title = "Free"
        colFree.width = 85
        tableView.addTableColumn(colFree)
        
        let colGraph = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Graph"))
        colGraph.title = "% Used"
        colGraph.width = 80
        tableView.addTableColumn(colGraph)
        
        scroll.documentView = tableView
        view.addSubview(scroll)
        
        // 3. Radio Group: A Folder
        radioFolder = NSButton(radioButtonWithTitle: "A Folder", target: self, action: #selector(radioChanged))
        radioFolder.frame = NSRect(x: 20, y: 115, width: 200, height: 22)
        view.addSubview(radioFolder)
        
        folderPathField = NSTextField(string: FileManager.default.homeDirectoryForCurrentUser.path)
        folderPathField.frame = NSRect(x: 40, y: 80, width: 380, height: 24)
        folderPathField.isEnabled = false
        view.addSubview(folderPathField)
        
        browseButton = NSButton(title: "Browse...", target: self, action: #selector(browseFolder))
        browseButton.bezelStyle = .rounded
        browseButton.frame = NSRect(x: 428, y: 77, width: 95, height: 28)
        browseButton.isEnabled = false
        view.addSubview(browseButton)
        
        // Buttons
        okButton = NSButton(title: "OK", target: self, action: #selector(confirmSelection))
        okButton.bezelStyle = .rounded
        okButton.frame = NSRect(x: 440, y: 18, width: 85, height: 32)
        okButton.keyEquivalent = "\r"
        view.addSubview(okButton)
        
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(closeWindow))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: 345, y: 18, width: 85, height: 32)
        view.addSubview(cancelButton)
    }
    
    @objc private func radioChanged() {
        if radioAllDrives.state == .on {
            tableView.isEnabled = false
            folderPathField.isEnabled = false
            browseButton.isEnabled = false
        } else if radioIndividualDrives.state == .on {
            tableView.isEnabled = true
            folderPathField.isEnabled = false
            browseButton.isEnabled = false
        } else if radioFolder.state == .on {
            tableView.isEnabled = false
            folderPathField.isEnabled = true
            browseButton.isEnabled = true
        }
    }
    
    @objc private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            chosenFolderURL = url
            folderPathField.stringValue = url.path
        }
    }
    
    @objc private func confirmSelection() {
        var targets: [URL] = []
        if radioAllDrives.state == .on {
            targets = volumes.map { $0.url }
        } else if radioIndividualDrives.state == .on {
            targets = volumes.filter { $0.isSelected }.map { $0.url }
            if targets.isEmpty {
                targets = [URL(fileURLWithPath: "/")]
            }
        } else if radioFolder.state == .on {
            let path = folderPathField.stringValue
            targets = [chosenFolderURL ?? URL(fileURLWithPath: path)]
        }
        
        delegate?.didSelectScanTarget(urls: targets)
        window?.close()
    }
    
    @objc private func closeWindow() {
        window?.close()
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return volumes.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn, row < volumes.count else { return nil }
        let volume = volumes[row]
        let id = col.identifier
        
        if id.rawValue == "Check" {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleDriveCheck(_:)))
            check.tag = row
            check.state = volume.isSelected ? .on : .off
            return check
        }
        
        let cell = NSTableCellView()
        let tf = NSTextField(frame: NSRect(x: 0, y: 2, width: col.width, height: 18))
        tf.isBordered = false
        tf.isEditable = false
        tf.drawsBackground = false
        tf.font = NSFont.systemFont(ofSize: 12)
        cell.addSubview(tf)
        cell.textField = tf
        
        switch id.rawValue {
        case "Name":
            tf.stringValue = (volume.isRemovable ? "💾 " : "💽 ") + volume.name
        case "Total":
            tf.stringValue = ByteCountFormatter.string(fromByteCount: Int64(volume.totalCapacity), countStyle: .file)
            tf.alignment = .right
        case "Free":
            tf.stringValue = ByteCountFormatter.string(fromByteCount: Int64(volume.freeCapacity), countStyle: .file)
            tf.alignment = .right
        case "Graph":
            let pct = Int(volume.percentUsed * 100)
            tf.stringValue = "\(pct)%"
            tf.alignment = .right
        default:
            break
        }
        return cell
    }
    
    @objc private func toggleDriveCheck(_ sender: NSButton) {
        let row = sender.tag
        if row < volumes.count {
            volumes[row].isSelected = (sender.state == .on)
        }
    }
}
