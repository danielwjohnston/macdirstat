import Cocoa
import MetalKit
import simd

public struct MetalTileInstance {
    var rect: SIMD4<Float>       // x, y, width, height
    var color: SIMD4<Float>      // r, g, b, a
    var surface: SIMD4<Float>    // s0, s1, s2, s3
    var isSelected: Float
    var padding: (Float, Float, Float) = (0, 0, 0)
}

public struct MetalUniforms {
    var viewportSize: SIMD2<Float>
    var lightVector: SIMD4<Float>  // lx, ly, lz, ambientLight
    var gridColor: SIMD4<Float>
}

@MainActor
public final class MetalTreemapRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    
    private var instanceBuffer: MTLBuffer?
    private var instanceCount: Int = 0
    
    public weak var view: MTKView?
    public var displayedRootItem: FileItem?
    public var selectedItem: FileItem?
    public var paletteMode: ColorPaletteMode = .fileType
    
    public init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        super.init()
        setupPipeline()
    }
    
    private func setupPipeline() {
        do {
            let library: MTLLibrary
            if let defaultLib = device.makeDefaultLibrary() {
                library = defaultLib
            } else {
                // If compiled embedded shaders aren't in the default bundle, compile from source at runtime
                let bundle = Bundle.main
                if let shaderURL = bundle.url(forResource: "default", withExtension: "metallib"),
                   let lib = try? device.makeLibrary(URL: shaderURL) {
                    library = lib
                } else if let shaderFile = bundle.url(forResource: "Shaders", withExtension: "metal"),
                          let source = try? String(contentsOf: shaderFile, encoding: .utf8) {
                    library = try device.makeLibrary(source: source, options: nil)
                } else {
                    // Fallback: compile inline shader string directly
                    let inlineShader = """
                    #include <metal_stdlib>
                    using namespace metal;

                    struct TileInstance {
                        float4 rect;
                        float4 color;
                        float4 surface;
                        float isSelected;
                        float padding[3];
                    };

                    struct Uniforms {
                        float2 viewportSize;
                        float4 lightVector;
                        float4 gridColor;
                    };

                    struct VertexOut {
                        float4 position [[position]];
                        float2 localPos;
                        float4 rect;
                        float4 color;
                        float4 surface;
                        float isSelected;
                    };

                    vertex VertexOut treemapVertexShader(
                        uint vertexID [[vertex_id]],
                        uint instanceID [[instance_id]],
                        constant TileInstance* instances [[buffer(0)]],
                        constant Uniforms& uniforms [[buffer(1)]]
                    ) {
                        const float2 unitQuad[6] = {
                            float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
                            float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
                        };
                        TileInstance tile = instances[instanceID];
                        float2 corner = unitQuad[vertexID];
                        float2 pixelPos = tile.rect.xy + corner * tile.rect.zw;
                        float2 ndc;
                        ndc.x = (pixelPos.x / uniforms.viewportSize.x) * 2.0 - 1.0;
                        ndc.y = 1.0 - (pixelPos.y / uniforms.viewportSize.y) * 2.0;

                        VertexOut out;
                        out.position = float4(ndc, 0.0, 1.0);
                        out.localPos = pixelPos;
                        out.rect = tile.rect;
                        out.color = tile.color;
                        out.surface = tile.surface;
                        out.isSelected = tile.isSelected;
                        return out;
                    }

                    fragment float4 treemapFragmentShader(
                        VertexOut in [[stage_in]],
                        constant Uniforms& uniforms [[buffer(1)]]
                    ) {
                        float2 pos = in.localPos;
                        float4 rect = in.rect;
                        float distLeft = pos.x - rect.x;
                        float distRight = (rect.x + rect.z) - pos.x;
                        float distTop = pos.y - rect.y;
                        float distBottom = (rect.y + rect.w) - pos.y;
                        float minDist = min(min(distLeft, distRight), min(distTop, distBottom));

                        if (in.isSelected > 0.5) {
                            if (minDist < 2.0) return float4(1.0, 1.0, 1.0, 1.0);
                        } else {
                            if (minDist < 0.6) return uniforms.gridColor;
                        }

                        float nx = -(2.0 * in.surface.x * pos.x + in.surface.z);
                        float ny = -(2.0 * in.surface.y * pos.y + in.surface.w);
                        float lx = uniforms.lightVector.x;
                        float ly = uniforms.lightVector.y;
                        float lz = uniforms.lightVector.z;
                        float Ia = uniforms.lightVector.w;
                        float Is = 1.0 - Ia;

                        float denom = sqrt(nx * nx + ny * ny + 1.0);
                        float cosa = clamp((nx * lx + ny * ly + lz) / denom, 0.0, 1.0);
                        float intensity = clamp(Is * cosa + Ia, 0.0, 1.0);
                        float3 baseColor = in.color.rgb;
                        float3 shaded = baseColor * (intensity * 1.25);
                        return float4(clamp(shaded, 0.0, 1.0), in.color.a);
                    }
                    """
                    library = try device.makeLibrary(source: inlineShader, options: nil)
                }
            }
            
            let vertexFunc = library.makeFunction(name: "treemapVertexShader")
            let fragmentFunc = library.makeFunction(name: "treemapFragmentShader")
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to initialize Metal treemap pipeline: \(error)")
        }
    }
    
    public func updateGeometry() {
        guard let root = displayedRootItem, let view = view else {
            instanceCount = 0
            return
        }
        
        let bounds = view.bounds
        TreeMapEngine.layout(item: root, in: bounds)
        
        var instances: [MetalTileInstance] = []
        instances.reserveCapacity(4096)
        
        var initialSurface: [Double] = [0.0, 0.0, 0.0, 0.0]
        let baseRidge = Double(AppSettings.shared.cushionIntensity)
        
        collectInstances(
            item: root,
            surface: &initialSurface,
            ridgeHeight: baseRidge,
            depth: 0,
            instances: &instances
        )
        
        self.instanceCount = instances.count
        if !instances.isEmpty {
            let bufferSize = instances.count * MemoryLayout<MetalTileInstance>.stride
            if instanceBuffer == nil || instanceBuffer!.length < bufferSize {
                instanceBuffer = device.makeBuffer(bytes: instances, length: bufferSize, options: .storageModeShared)
            } else {
                instanceBuffer?.contents().copyMemory(from: instances, byteCount: bufferSize)
            }
        }
    }
    
    private func collectInstances(
        item: FileItem,
        surface: inout [Double],
        ridgeHeight: Double,
        depth: Int,
        instances: inout [MetalTileInstance]
    ) {
        let minPixel = AppSettings.shared.minTileSize
        
        var localSurface = surface
        if depth > 0 && item.bounds.width > 0 && item.bounds.height > 0 {
            addRidge(rect: item.bounds, surface: &localSurface, h: ridgeHeight)
        }
        
        if item.children.isEmpty || (!item.isDirectory || item.isPackage) {
            if item.bounds.width >= minPixel && item.bounds.height >= minPixel {
                let color = colorForItem(item)
                let isSel: Float = (item === selectedItem) ? 1.0 : 0.0
                
                let rect = SIMD4<Float>(
                    Float(item.bounds.origin.x),
                    Float(item.bounds.origin.y),
                    Float(item.bounds.size.width),
                    Float(item.bounds.size.height)
                )
                let col = SIMD4<Float>(
                    Float(color.redComponent),
                    Float(color.greenComponent),
                    Float(color.blueComponent),
                    Float(color.alphaComponent)
                )
                let surf = SIMD4<Float>(
                    Float(localSurface[0]),
                    Float(localSurface[1]),
                    Float(localSurface[2]),
                    Float(localSurface[3])
                )
                
                instances.append(MetalTileInstance(rect: rect, color: col, surface: surf, isSelected: isSel))
            }
        } else {
            let nextRidge = ridgeHeight * 0.91
            for child in item.children where child.size > 0 {
                var childSurface = localSurface
                collectInstances(item: child, surface: &childSurface, ridgeHeight: nextRidge, depth: depth + 1, instances: &instances)
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
    
    private func colorForItem(_ item: FileItem) -> NSColor {
        if item.isSpecialNode {
            return ExtensionColorManager.shared.color(for: item.name)
        }
        switch paletteMode {
        case .fileType:
            return ExtensionColorManager.shared.color(for: item.extensionName)
        case .fileAge:
            return ExtensionColorManager.shared.colorForAge(date: item.modificationDate)
        case .depth:
            var depth = 0
            var p = item.parent
            while p != nil {
                depth += 1
                p = p?.parent
            }
            let hue = CGFloat((depth * 37) % 360) / 360.0
            return NSColor(calibratedHue: hue, saturation: 0.75, brightness: 0.85, alpha: 1.0)
        }
    }
    
    // MARK: - MTKViewDelegate
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateGeometry()
    }
    
    public func draw(in view: MTKView) {
        guard let pipelineState = pipelineState,
              let instanceBuffer = instanceBuffer,
              instanceCount > 0,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        let viewport = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        let lx: Float = -1.0 / 10.099505
        let ly: Float = -1.0 / 10.099505
        let lz: Float = 10.0 / 10.099505
        let ambient: Float = 0.15
        
        let gridColorNS = AppSettings.shared.theme.treemapGridColor.usingColorSpace(.deviceRGB) ?? .black
        let grid = SIMD4<Float>(
            Float(gridColorNS.redComponent),
            Float(gridColorNS.greenComponent),
            Float(gridColorNS.blueComponent),
            Float(gridColorNS.alphaComponent)
        )
        
        var uniforms = MetalUniforms(
            viewportSize: viewport,
            lightVector: SIMD4<Float>(lx, ly, lz, ambient),
            gridColor: grid
        )
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 1)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
