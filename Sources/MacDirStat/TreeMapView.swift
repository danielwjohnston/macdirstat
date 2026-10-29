import Cocoa
import MetalKit
import Quartz

public enum ColorPaletteMode: String, CaseIterable {
    case fileType = "File Extension"
    case fileAge = "File Age (Heatmap)"
    case depth = "Folder Hierarchy"
}

@MainActor
public final class ExtensionColorManager {
    public static let shared = ExtensionColorManager()
    private var colorMap: [String: NSColor] = [:]
    private var nextIndex = 0
    
    public func color(for extensionName: String) -> NSColor {
        let key = extensionName.lowercased()
        if key == "<free space>" {
            return NSColor(calibratedWhite: 0.38, alpha: 1.0)
        }
        if key == "<unknown>" {
            return NSColor(calibratedWhite: 0.60, alpha: 1.0)
        }
        if let existing = colorMap[key] {
            return existing
        }
        let palette = AppSettings.shared.theme.palette()
        let color = palette[nextIndex % palette.count]
        nextIndex += 1
        colorMap[key] = color
        return color
    }
    
    public func resetPalette() {
        colorMap.removeAll()
        nextIndex = 0
    }
    
    public func colorForAge(date: Date?) -> NSColor {
        guard let date = date else {
            return NSColor(calibratedWhite: 0.45, alpha: 1.0)
        }
        let daysAgo = max(0, Date().timeIntervalSince(date) / 86400.0)
        if daysAgo < 7 {
            return NSColor(calibratedRed: 0.95, green: 0.22, blue: 0.22, alpha: 1.0)
        } else if daysAgo < 30 {
            return NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1.0)
        } else if daysAgo < 180 {
            return NSColor(calibratedRed: 0.90, green: 0.82, blue: 0.15, alpha: 1.0)
        } else if daysAgo < 365 {
            return NSColor(calibratedRed: 0.25, green: 0.75, blue: 0.35, alpha: 1.0)
        } else {
            return NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.90, alpha: 1.0)
        }
    }
}

@MainActor
public protocol TreeMapSelectionDelegate: AnyObject {
    func didSelect(item: FileItem)
    func didDoubleClick(item: FileItem)
    func showContextMenu(for item: FileItem, at point: CGPoint)
}

public final class TreeMapView: NSView {
    public weak var delegate: TreeMapSelectionDelegate?
    
    private var mtkView: MTKView?
    private var metalRenderer: MetalTreemapRenderer?
    
    public var displayedRootItem: FileItem? {
        didSet {
            metalRenderer?.displayedRootItem = displayedRootItem
            metalRenderer?.updateGeometry()
            mtkView?.setNeedsDisplay(bounds)
            setNeedsDisplay(bounds)
        }
    }
    
    public var selectedItem: FileItem? {
        didSet {
            metalRenderer?.selectedItem = selectedItem
            metalRenderer?.updateGeometry()
            mtkView?.setNeedsDisplay(bounds)
            setNeedsDisplay(bounds)
        }
    }
    
    public var paletteMode: ColorPaletteMode = .fileType {
        didSet {
            metalRenderer?.paletteMode = paletteMode
            metalRenderer?.updateGeometry()
            mtkView?.setNeedsDisplay(bounds)
            setNeedsDisplay(bounds)
        }
    }
    
    public override var isFlipped: Bool {
        return true
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        setupMetal()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        setupMetal()
    }
    
    private func setupMetal() {
        if let device = MTLCreateSystemDefaultDevice() {
            let mtk = MTKView(frame: bounds, device: device)
            mtk.autoresizingMask = [.width, .height]
            mtk.colorPixelFormat = .bgra8Unorm
            mtk.clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
            mtk.isPaused = true
            mtk.enableSetNeedsDisplay = true
            
            if let renderer = MetalTreemapRenderer(device: device) {
                renderer.view = mtk
                mtk.delegate = renderer
                self.metalRenderer = renderer
                self.mtkView = mtk
                addSubview(mtk)
            }
        }
    }
    
    public override func layout() {
        super.layout()
        if let root = displayedRootItem {
            TreeMapEngine.layout(item: root, in: bounds)
            metalRenderer?.updateGeometry()
            mtkView?.setNeedsDisplay(bounds)
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // If Metal is active and rendering in MTKView, update clear color and trigger redraw
        if let mtk = mtkView {
            let canvasColor = AppSettings.shared.theme.treemapCanvasBackgroundColor
            if let rgb = canvasColor.usingColorSpace(.deviceRGB) {
                mtk.clearColor = MTLClearColor(
                    red: Double(rgb.redComponent),
                    green: Double(rgb.greenComponent),
                    blue: Double(rgb.blueComponent),
                    alpha: 1.0
                )
            }
            mtk.setNeedsDisplay(dirtyRect)
            return
        }
        
        // CPU fallback if Metal device unavailable
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let theme = AppSettings.shared.theme
        let canvasColor = theme.treemapCanvasBackgroundColor
        context.setFillColor(canvasColor.cgColor)
        context.fill(bounds)
        
        guard let root = displayedRootItem else { return }
        var initialSurface: [Double] = [0.0, 0.0, 0.0, 0.0]
        let baseRidgeHeight = Double(AppSettings.shared.cushionIntensity)
        drawTree(item: root, surface: &initialSurface, ridgeHeight: baseRidgeHeight, depth: 0, in: context)
    }
    
    private func drawTree(
        item: FileItem,
        surface: inout [Double],
        ridgeHeight: Double,
        depth: Int,
        in context: CGContext
    ) {
        let minPixel = AppSettings.shared.minTileSize
        
        var localSurface = surface
        if depth > 0 && item.bounds.width > 0 && item.bounds.height > 0 {
            addRidge(rect: item.bounds, surface: &localSurface, h: ridgeHeight)
        }
        
        if item.children.isEmpty || (!item.isDirectory || item.isPackage) {
            if item.bounds.width >= minPixel && item.bounds.height >= minPixel {
                drawCushionTile(item: item, surface: localSurface, in: context)
            }
        } else {
            let nextRidge = ridgeHeight * 0.91
            for child in item.children where child.size > 0 {
                var childSurface = localSurface
                drawTree(item: child, surface: &childSurface, ridgeHeight: nextRidge, depth: depth + 1, in: context)
            }
        }
    }
    
    private func addRidge(rect: CGRect, surface: inout [Double], h: Double) {
        let width = rect.width
        let height = rect.height
        guard width > 0 && height > 0 else { return }
        
        let h4 = 4.0 * h
        let wf = h4 / Double(width)
        surface[2] += wf * Double(rect.maxX + rect.minX)
        surface[0] -= wf
        
        let hf = h4 / Double(height)
        surface[3] += hf * Double(rect.maxY + rect.minY)
        surface[1] -= hf
    }
    
    private func drawCushionTile(item: FileItem, surface: [Double], in context: CGContext) {
        let rect = item.bounds
        let baseColor: NSColor
        if item.isSpecialNode {
            baseColor = ExtensionColorManager.shared.color(for: item.name)
        } else {
            switch paletteMode {
            case .fileType:
                baseColor = ExtensionColorManager.shared.color(for: item.extensionName)
            case .fileAge:
                baseColor = ExtensionColorManager.shared.colorForAge(date: item.modificationDate)
            case .depth:
                var depth = 0
                var p = item.parent
                while p != nil {
                    depth += 1
                    p = p?.parent
                }
                let hue = CGFloat((depth * 37) % 360) / 360.0
                baseColor = NSColor(calibratedHue: hue, saturation: 0.75, brightness: 0.85, alpha: 1.0)
            }
        }
        
        context.saveGState()
        let lx: CGFloat = -1.0 / 10.099505
        let ly: CGFloat = -1.0 / 10.099505
        let lz: CGFloat = 10.0 / 10.099505
        let ambientLight: CGFloat = 0.15
        let isDiffuse: CGFloat = 1.0 - ambientLight
        
        let midX = rect.midX
        let midY = rect.midY
        
        let nxMid = CGFloat(-(2.0 * surface[0] * Double(midX) + surface[2]))
        let nyMid = CGFloat(-(2.0 * surface[1] * Double(midY) + surface[3]))
        let denomMid = sqrt(nxMid * nxMid + nyMid * nyMid + 1.0)
        let cosMid = max(0.0, min(1.0, (nxMid * lx + nyMid * ly + lz) / denomMid))
        let centerIntensity = min(1.0, isDiffuse * cosMid + ambientLight)
        
        let nxTopLeft = CGFloat(-(2.0 * surface[0] * Double(rect.minX) + surface[2]))
        let nyTopLeft = CGFloat(-(2.0 * surface[1] * Double(rect.minY) + surface[3]))
        let denomTL = sqrt(nxTopLeft * nxTopLeft + nyTopLeft * nyTopLeft + 1.0)
        let cosTL = max(0.0, min(1.0, (nxTopLeft * lx + nyTopLeft * ly + lz) / denomTL))
        let topIntensity = min(1.0, isDiffuse * cosTL + ambientLight)
        
        let nxBottomRight = CGFloat(-(2.0 * surface[0] * Double(rect.maxX) + surface[2]))
        let nyBottomRight = CGFloat(-(2.0 * surface[1] * Double(rect.maxY) + surface[3]))
        let denomBR = sqrt(nxBottomRight * nxBottomRight + nyBottomRight * nyBottomRight + 1.0)
        let cosBR = max(0.0, min(1.0, (nxBottomRight * lx + nyBottomRight * ly + lz) / denomBR))
        let bottomIntensity = min(1.0, isDiffuse * cosBR + ambientLight)
        
        let highlight = adjustBrightness(of: baseColor, factor: topIntensity * 1.35)
        let midTone = adjustBrightness(of: baseColor, factor: centerIntensity * 1.05)
        let shadow = adjustBrightness(of: baseColor, factor: bottomIntensity * 0.70)
        
        let colors = [highlight.cgColor, midTone.cgColor, shadow.cgColor] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.42, 1.0]) {
            context.clip(to: rect)
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        } else {
            context.setFillColor(baseColor.cgColor)
            context.fill(rect)
        }
        
        if item === selectedItem {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2.0)
            context.stroke(rect.insetBy(dx: 1, dy: 1))
        } else {
            let gridColor = AppSettings.shared.theme.treemapGridColor
            context.setStrokeColor(gridColor.cgColor)
            context.setLineWidth(0.5)
            context.stroke(rect)
        }
        
        context.restoreGState()
    }
    
    private func adjustBrightness(of color: NSColor, factor: CGFloat) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        let r = min(1.0, max(0.0, rgb.redComponent * factor))
        let g = min(1.0, max(0.0, rgb.greenComponent * factor))
        let b = min(1.0, max(0.0, rgb.blueComponent * factor))
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        // Redirect all mouse events from MTKView child directly to this TreeMapView
        let viewPoint = convert(point, from: superview)
        if bounds.contains(viewPoint) {
            return self
        }
        return super.hitTest(point)
    }
    
    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitTestItem(root: displayedRootItem, point: point) {
            selectedItem = hit
            delegate?.didSelect(item: hit)
            
            if event.clickCount == 2 {
                delegate?.didDoubleClick(item: hit)
            }
        }
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitTestItem(root: displayedRootItem, point: point) {
            selectedItem = hit
            delegate?.didSelect(item: hit)
            delegate?.showContextMenu(for: hit, at: point)
        }
    }
    
    private func hitTestItem(root: FileItem?, point: CGPoint) -> FileItem? {
        guard let root = root, root.bounds.contains(point) else { return nil }
        if root.children.isEmpty || (!root.isDirectory || root.isPackage) {
            return root
        }
        for child in root.children {
            if let found = hitTestItem(root: child, point: point) {
                return found
            }
        }
        return root
    }
}
