import Cocoa

public enum AppTheme: String, CaseIterable, Sendable {
    case classic = "Faithful WinDirStat (Classic)"
    case system = "macOS System"
    case dracula = "Dracula"
    case alucard = "Alucard"
    case nord = "Nord"
    
    /// Determines whether the current system appearance is dark
    @MainActor
    private static var isSystemDark: Bool {
        if let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing() as NSAppearance? {
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return false
    }
    
    @MainActor
    public var windowBackgroundColor: NSColor {
        let dark = AppTheme.isSystemDark
        switch self {
        case .classic:
            // Faithful Win32 Dialog Grey in light mode; authentic charcoal classic Win32 dark theme in dark mode
            return dark
                ? NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.18, alpha: 1.0)
                : NSColor(calibratedRed: 0.83, green: 0.81, blue: 0.78, alpha: 1.0) // #d4d0c8
        case .system:
            return .windowBackgroundColor
        case .dracula:
            return dark
                ? NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.21, alpha: 1.0) // #282a36
                : NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.96, alpha: 1.0) // Dracula Day
        case .alucard:
            return dark
                ? NSColor(calibratedRed: 0.08, green: 0.07, blue: 0.09, alpha: 1.0) // Deep obsidian
                : NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.94, alpha: 1.0) // Crimson Pearl
        case .nord:
            return dark
                ? NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1.0) // Polar Night #2e3440
                : NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.96, alpha: 1.0) // Snow Storm #eceff4
        }
    }
    
    @MainActor
    public var controlBackgroundColor: NSColor {
        let dark = AppTheme.isSystemDark
        switch self {
        case .classic:
            return dark
                ? NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
                : .white
        case .system:
            return .controlBackgroundColor
        case .dracula:
            return dark
                ? NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.35, alpha: 1.0) // #44475a
                : .white
        case .alucard:
            return dark
                ? NSColor(calibratedRed: 0.14, green: 0.12, blue: 0.16, alpha: 1.0)
                : .white
        case .nord:
            return dark
                ? NSColor(calibratedRed: 0.23, green: 0.26, blue: 0.32, alpha: 1.0) // Nord 1 #3b4252
                : .white
        }
    }
    
    @MainActor
    public var textColor: NSColor {
        let dark = AppTheme.isSystemDark
        switch self {
        case .classic:
            return dark ? NSColor(calibratedWhite: 0.94, alpha: 1.0) : .black
        case .system:
            return .labelColor
        case .dracula:
            return dark
                ? NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.95, alpha: 1.0) // #f8f8f2
                : NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.21, alpha: 1.0)
        case .alucard:
            return dark
                ? NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.94, alpha: 1.0)
                : NSColor(calibratedRed: 0.12, green: 0.05, blue: 0.08, alpha: 1.0)
        case .nord:
            return dark
                ? NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0) // #eceff4
                : NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1.0) // #2e3440
        }
    }
    
    @MainActor
    public var secondaryTextColor: NSColor {
        let dark = AppTheme.isSystemDark
        switch self {
        case .classic:
            return dark ? NSColor(calibratedWhite: 0.65, alpha: 1.0) : NSColor(calibratedWhite: 0.35, alpha: 1.0)
        case .system:
            return .secondaryLabelColor
        case .dracula:
            return dark
                ? NSColor(calibratedRed: 0.38, green: 0.44, blue: 0.64, alpha: 1.0) // #6272a4
                : NSColor(calibratedRed: 0.40, green: 0.42, blue: 0.52, alpha: 1.0)
        case .alucard:
            return dark
                ? NSColor(calibratedRed: 0.65, green: 0.45, blue: 0.55, alpha: 1.0)
                : NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.40, alpha: 1.0)
        case .nord:
            return dark
                ? NSColor(calibratedRed: 0.56, green: 0.60, blue: 0.68, alpha: 1.0) // Nord 4
                : NSColor(calibratedRed: 0.40, green: 0.45, blue: 0.55, alpha: 1.0)
        }
    }
    
    @MainActor
    public var treemapCanvasBackgroundColor: NSColor {
        let dark = AppTheme.isSystemDark
        switch self {
        case .classic:
            // Authentic WinDirStat: dark sunken viewport frame (#1a1a1a)
            return NSColor(calibratedWhite: 0.12, alpha: 1.0)
        case .system:
            return dark ? NSColor(calibratedWhite: 0.10, alpha: 1.0) : NSColor(calibratedWhite: 0.90, alpha: 1.0)
        case .dracula:
            return dark ? NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.18, alpha: 1.0) : NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.93, alpha: 1.0)
        case .alucard:
            return dark ? NSColor(calibratedRed: 0.05, green: 0.04, blue: 0.06, alpha: 1.0) : NSColor(calibratedRed: 0.92, green: 0.88, blue: 0.90, alpha: 1.0)
        case .nord:
            return dark ? NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.21, alpha: 1.0) : NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.94, alpha: 1.0)
        }
    }
    
    @MainActor
    public var treemapGridColor: NSColor {
        let dark = AppTheme.isSystemDark
        if isClassicWin32 {
            return NSColor(calibratedWhite: 0.0, alpha: 0.85)
        }
        return dark ? NSColor(calibratedWhite: 0.0, alpha: 0.75) : NSColor(calibratedWhite: 0.0, alpha: 0.35)
    }
    
    public var isClassicWin32: Bool {
        return self == .classic
    }
    
    /// Signature WinDirStat 18-color default palette ported verbatim from TreeMap.h / DefaultCushionColors
    public func palette() -> [NSColor] {
        switch self {
        case .classic, .system:
            return [
                NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0),       // Blue
                NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),       // Red
                NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),       // Green
                NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0),       // Yellow
                NSColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0),       // Cyan
                NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0),       // Magenta
                NSColor(red: 1.0, green: 0.667, blue: 0.0, alpha: 1.0),     // Orange
                NSColor(red: 0.0, green: 0.333, blue: 1.0, alpha: 1.0),     // Dodger Blue
                NSColor(red: 1.0, green: 0.0, blue: 0.333, alpha: 1.0),     // Hot Pink
                NSColor(red: 0.333, green: 1.0, blue: 0.0, alpha: 1.0),     // Lime Green
                NSColor(red: 0.667, green: 0.0, blue: 1.0, alpha: 1.0),     // Violet
                NSColor(red: 0.0, green: 1.0, blue: 0.333, alpha: 1.0),     // Spring Green
                NSColor(red: 1.0, green: 0.0, blue: 0.667, alpha: 1.0),     // Deep Pink
                NSColor(red: 0.0, green: 0.667, blue: 1.0, alpha: 1.0),     // Sky Blue
                NSColor(red: 1.0, green: 0.333, blue: 0.0, alpha: 1.0),     // Orange Red
                NSColor(red: 0.0, green: 1.0, blue: 0.667, alpha: 1.0),     // Aquamarine
                NSColor(red: 0.333, green: 0.0, blue: 1.0, alpha: 1.0),     // Indigo
            ]
        case .dracula:
            return [
                NSColor(calibratedRed: 0.94, green: 0.47, blue: 0.76, alpha: 1.0), // Pink (#ff79c6)
                NSColor(calibratedRed: 0.74, green: 0.58, blue: 0.98, alpha: 1.0), // Purple (#bd93f9)
                NSColor(calibratedRed: 0.55, green: 0.91, blue: 0.99, alpha: 1.0), // Cyan (#8be9fd)
                NSColor(calibratedRed: 0.31, green: 0.98, blue: 0.48, alpha: 1.0), // Green (#50fa7b)
                NSColor(calibratedRed: 0.95, green: 0.99, blue: 0.55, alpha: 1.0), // Yellow (#f1fa8c)
                NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.42, alpha: 1.0), // Orange (#ffb86c)
                NSColor(calibratedRed: 1.00, green: 0.33, blue: 0.33, alpha: 1.0), // Red (#ff5555)
            ]
        case .alucard:
            return [
                NSColor(calibratedRed: 0.92, green: 0.12, blue: 0.25, alpha: 1.0), // Blood Crimson
                NSColor(calibratedRed: 0.80, green: 0.15, blue: 0.55, alpha: 1.0), // Dark Carmine
                NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.15, alpha: 1.0), // Amber fire
                NSColor(calibratedRed: 0.50, green: 0.15, blue: 0.75, alpha: 1.0), // Night purple
                NSColor(calibratedRed: 0.20, green: 0.65, blue: 0.85, alpha: 1.0), // Spectral blue
                NSColor(calibratedRed: 0.75, green: 0.70, blue: 0.72, alpha: 1.0), // Bone silver
            ]
        case .nord:
            return [
                NSColor(calibratedRed: 0.53, green: 0.75, blue: 0.82, alpha: 1.0), // Nord 8 (Frost Cyan #88c0d0)
                NSColor(calibratedRed: 0.51, green: 0.63, blue: 0.76, alpha: 1.0), // Nord 9 (Frost Blue #81a1c1)
                NSColor(calibratedRed: 0.37, green: 0.51, blue: 0.67, alpha: 1.0), // Nord 10 (Deep Frost #5e81ac)
                NSColor(calibratedRed: 0.64, green: 0.75, blue: 0.55, alpha: 1.0), // Nord 14 (Aurora Green #a3be8c)
                NSColor(calibratedRed: 0.92, green: 0.79, blue: 0.54, alpha: 1.0), // Nord 13 (Aurora Yellow #ebcb8b)
                NSColor(calibratedRed: 0.82, green: 0.53, blue: 0.44, alpha: 1.0), // Nord 12 (Aurora Orange #d08770)
                NSColor(calibratedRed: 0.75, green: 0.43, blue: 0.52, alpha: 1.0), // Nord 11 (Aurora Red #bf616a)
                NSColor(calibratedRed: 0.71, green: 0.56, blue: 0.68, alpha: 1.0), // Nord 15 (Aurora Purple #b48ead)
            ]
        }
    }
}

public struct UserCleanupCommand: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var title: String
    public var commandTemplate: String
    
    public init(title: String, commandTemplate: String) {
        self.title = title
        self.commandTemplate = commandTemplate
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    private let themeKey = "MacDirStat.Theme"
    private let minTileKey = "MacDirStat.MinTileSize"
    private let cushionIntensityKey = "MacDirStat.CushionIntensity"
    private let showFreeSpaceKey = "MacDirStat.ShowFreeSpace"
    
    public var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
            NotificationCenter.default.post(name: NSNotification.Name("ThemeChangedNotification"), object: nil)
        }
    }
    
    public var minTileSize: CGFloat {
        didSet { UserDefaults.standard.set(minTileSize, forKey: minTileKey) }
    }
    
    public var cushionIntensity: CGFloat {
        didSet { UserDefaults.standard.set(cushionIntensity, forKey: cushionIntensityKey) }
    }
    
    public var showFreeSpace: Bool {
        didSet { UserDefaults.standard.set(showFreeSpace, forKey: showFreeSpaceKey) }
    }
    
    public var cleanups: [UserCleanupCommand] = [
        UserCleanupCommand(title: "Open in Terminal", commandTemplate: "open -a Terminal \"%p\""),
        UserCleanupCommand(title: "Copy File Size", commandTemplate: "echo \"%s\" | pbcopy"),
        UserCleanupCommand(title: "Quick Look Preview", commandTemplate: "qlmanage -p \"%p\" >/dev/null 2>&1 &"),
    ]
    
    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: themeKey) ?? AppTheme.classic.rawValue
        self.theme = AppTheme(rawValue: savedTheme) ?? .classic
        
        let savedMinTile = UserDefaults.standard.double(forKey: minTileKey)
        self.minTileSize = savedMinTile > 0 ? CGFloat(savedMinTile) : 1.0
        
        let savedCushion = UserDefaults.standard.double(forKey: cushionIntensityKey)
        self.cushionIntensity = savedCushion > 0 ? CGFloat(savedCushion) : 0.38
        
        if UserDefaults.standard.object(forKey: showFreeSpaceKey) != nil {
            self.showFreeSpace = UserDefaults.standard.bool(forKey: showFreeSpaceKey)
        } else {
            self.showFreeSpace = true
        }
    }
}
