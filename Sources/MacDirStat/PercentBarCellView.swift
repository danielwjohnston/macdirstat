import Cocoa

public final class PercentBarCellView: NSTableCellView {
    public var percentage: Double = 0.0 {
        didSet {
            setNeedsDisplay(bounds)
        }
    }
    
    public var barColor: NSColor = NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.95, alpha: 1.0)
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let insetRect = bounds.insetBy(dx: 4, dy: 3)
        let theme = AppSettings.shared.theme
        let isDark = (NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        
        // Background sunken track
        let trackColor = isDark
            ? NSColor(calibratedWhite: 0.15, alpha: 0.6)
            : NSColor(calibratedWhite: 0.88, alpha: 1.0)
        ctx.setFillColor(trackColor.cgColor)
        ctx.fill(insetRect)
        
        // Progress fill
        let fillWidth = max(0, insetRect.width * CGFloat(min(1.0, max(0.0, percentage))))
        if fillWidth > 0 {
            let fillRect = CGRect(x: insetRect.minX, y: insetRect.minY, width: fillWidth, height: insetRect.height)
            
            // WinDirStat signature 3D beveled bar gradient
            let lightColor = barColor.blended(withFraction: 0.35, of: .white) ?? barColor
            let darkColor = barColor.blended(withFraction: 0.40, of: .black) ?? barColor
            let colors = [
                lightColor.cgColor,
                barColor.cgColor,
                darkColor.cgColor
            ] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.45, 1.0]) {
                ctx.saveGState()
                ctx.clip(to: fillRect)
                ctx.drawLinearGradient(gradient, start: CGPoint(x: fillRect.minX, y: fillRect.minY), end: CGPoint(x: fillRect.minX, y: fillRect.maxY), options: [])
                ctx.restoreGState()
            }
        }
        
        // Sunken border
        let strokeColor = isDark
            ? NSColor(calibratedWhite: 0.05, alpha: 0.8)
            : NSColor(calibratedWhite: 0.55, alpha: 0.9)
        ctx.setStrokeColor(strokeColor.cgColor)
        ctx.setLineWidth(0.75)
        ctx.stroke(insetRect)
        
        // Text overlay: e.g. "42.5%"
        let pctText = String(format: "%.1f%%", percentage * 100.0)
        // High contrast text: white in dark mode or on dark bars, dark text in light tracks
        let textColor: NSColor
        if percentage > 0.45 {
            textColor = .white
        } else {
            textColor = theme.textColor
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: textColor
        ]
        let str = NSAttributedString(string: pctText, attributes: attrs)
        let strSize = str.size()
        let textPoint = CGPoint(
            x: insetRect.midX - strSize.width / 2.0,
            y: insetRect.midY - strSize.height / 2.0
        )
        str.draw(at: textPoint)
    }
}
