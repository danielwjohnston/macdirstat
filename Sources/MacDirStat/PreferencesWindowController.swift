import Cocoa

public final class PreferencesWindowController: NSWindowController {
    
    private var themePopUp: NSPopUpButton!
    private var freeSpaceCheckbox: NSButton!
    private var minTileSlider: NSSlider!
    private var minTileLabel: NSTextField!
    private var cushionSlider: NSSlider!
    private var cushionLabel: NSTextField!
    
    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacDirStat Preferences & Theming"
        self.init(window: window)
        setupUI()
    }
    
    private func setupUI() {
        guard let window = window else { return }
        let view = NSView(frame: window.contentView!.bounds)
        window.contentView = view
        
        let settings = AppSettings.shared
        
        // 1. Theme Selector
        let themeLabel = NSTextField(labelWithString: "Visual Theme:")
        themeLabel.frame = NSRect(x: 30, y: 260, width: 140, height: 20)
        themeLabel.font = NSFont.boldSystemFont(ofSize: 13)
        view.addSubview(themeLabel)
        
        themePopUp = NSPopUpButton(frame: NSRect(x: 180, y: 256, width: 260, height: 28), pullsDown: false)
        for theme in AppTheme.allCases {
            themePopUp.addItem(withTitle: theme.rawValue)
        }
        themePopUp.selectItem(withTitle: settings.theme.rawValue)
        themePopUp.target = self
        themePopUp.action = #selector(themeSelected)
        view.addSubview(themePopUp)
        
        // 2. Free Space
        freeSpaceCheckbox = NSButton(checkboxWithTitle: "Show <Free Space> and <Unknown> in volume scans", target: self, action: #selector(freeSpaceToggled))
        freeSpaceCheckbox.frame = NSRect(x: 30, y: 215, width: 420, height: 22)
        freeSpaceCheckbox.state = settings.showFreeSpace ? .on : .off
        view.addSubview(freeSpaceCheckbox)
        
        // 3. Min Tile Size Slider
        let minTileTitle = NSTextField(labelWithString: "Min Tile Size (px):")
        minTileTitle.frame = NSRect(x: 30, y: 165, width: 140, height: 20)
        view.addSubview(minTileTitle)
        
        minTileSlider = NSSlider(value: Double(settings.minTileSize), minValue: 1.0, maxValue: 10.0, target: self, action: #selector(minTileChanged))
        minTileSlider.frame = NSRect(x: 180, y: 165, width: 200, height: 20)
        view.addSubview(minTileSlider)
        
        minTileLabel = NSTextField(labelWithString: "\(Int(settings.minTileSize)) px")
        minTileLabel.frame = NSRect(x: 390, y: 165, width: 50, height: 20)
        view.addSubview(minTileLabel)
        
        // 4. Cushion Intensity Slider
        let cushionTitle = NSTextField(labelWithString: "Cushion Relief 3D:")
        cushionTitle.frame = NSRect(x: 30, y: 115, width: 140, height: 20)
        view.addSubview(cushionTitle)
        
        cushionSlider = NSSlider(value: Double(settings.cushionIntensity), minValue: 0.1, maxValue: 0.9, target: self, action: #selector(cushionChanged))
        cushionSlider.frame = NSRect(x: 180, y: 115, width: 200, height: 20)
        view.addSubview(cushionSlider)
        
        cushionLabel = NSTextField(labelWithString: String(format: "%.0f%%", settings.cushionIntensity * 100))
        cushionLabel.frame = NSRect(x: 390, y: 115, width: 50, height: 20)
        view.addSubview(cushionLabel)
        
        let closeBtn = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        closeBtn.bezelStyle = .rounded
        closeBtn.frame = NSRect(x: 360, y: 20, width: 90, height: 32)
        closeBtn.keyEquivalent = "\r"
        view.addSubview(closeBtn)
    }
    
    @objc private func themeSelected() {
        if let title = themePopUp.titleOfSelectedItem, let theme = AppTheme(rawValue: title) {
            AppSettings.shared.theme = theme
        }
    }
    
    @objc private func freeSpaceToggled() {
        AppSettings.shared.showFreeSpace = (freeSpaceCheckbox.state == .on)
    }
    
    @objc private func minTileChanged() {
        let val = CGFloat(minTileSlider.doubleValue)
        AppSettings.shared.minTileSize = val
        minTileLabel.stringValue = "\(Int(val)) px"
    }
    
    @objc private func cushionChanged() {
        let val = CGFloat(cushionSlider.doubleValue)
        AppSettings.shared.cushionIntensity = val
        cushionLabel.stringValue = String(format: "%.0f%%", val * 100)
    }
    
    @objc private func closeWindow() {
        window?.close()
    }
}
