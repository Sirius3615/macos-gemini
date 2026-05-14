import SwiftUI

struct DrawingPath: Identifiable {
    let id = UUID()
    var points: [CGPoint]
}

struct BlurRegion: Identifiable {
    let id = UUID()
    var rect: CGRect
}

struct ScreenshotEditorView: View {
    let originalImage: NSImage
    let onComplete: (Data?) -> Void
    
    @State private var mode: EditMode = .crop
    @State private var paths: [DrawingPath] = []
    @State private var currentPath: DrawingPath?
    
    // Blur/Redact state
    @State private var blurRegions: [BlurRegion] = []
    @State private var currentBlurStart: CGPoint?
    @State private var currentBlurRect: CGRect?
    
    // Crop state
    @State private var cropRect: CGRect?
    @State private var isDraggingCrop = false
    @State private var dragStartPoint: CGPoint = .zero
    
    // Geometry for rendering
    @State private var viewSize: CGSize = .zero
    
    enum EditMode: String, CaseIterable {
        case crop = "Crop"
        case draw = "Draw"
        case blur = "Redact"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Cancel") {
                    onComplete(nil)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Picker("", selection: $mode) {
                    ForEach(EditMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                
                Spacer()
                
                if !blurRegions.isEmpty || !paths.isEmpty || cropRect != nil {
                    Button("Clear All") {
                        blurRegions.removeAll()
                        paths.removeAll()
                        cropRect = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                
                Button("Done") {
                    finishEditing()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            
            // Mode hint
            HStack {
                Image(systemName: modeIcon)
                    .font(.system(size: 10))
                Text(modeHint)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.4))
            
            // Editor Area
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.3) // Background behind image
                    
                    let sizes = calculateRenderSize(viewSize: geometry.size)
                    
                    ZStack {
                        // The combined image and drawing
                        renderedContentView(width: sizes.width, height: sizes.height)
                        
                        // Interaction layer
                        interactionLayer(width: sizes.width, height: sizes.height)
                    }
                    .frame(width: sizes.width, height: sizes.height)
                }
                .onAppear {
                    self.viewSize = geometry.size
                }
                .onChange(of: geometry.size) { _, newSize in
                    self.viewSize = newSize
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private var modeIcon: String {
        switch mode {
        case .crop: return "crop"
        case .draw: return "pencil.tip"
        case .blur: return "eye.slash.fill"
        }
    }
    
    private var modeHint: String {
        switch mode {
        case .crop: return "Click and drag to select a crop region"
        case .draw: return "Draw annotations on the screenshot"
        case .blur: return "Drag over sensitive areas to redact them"
        }
    }
    
    private func calculateRenderSize(viewSize: CGSize) -> CGSize {
        let aspect = originalImage.size.width / originalImage.size.height
        let viewAspect = viewSize.width / viewSize.height
        
        var renderWidth: CGFloat
        var renderHeight: CGFloat
        
        if aspect > viewAspect {
            renderWidth = viewSize.width
            renderHeight = viewSize.width / aspect
        } else {
            renderHeight = viewSize.height
            renderWidth = viewSize.height * aspect
        }
        return CGSize(width: max(renderWidth, 0), height: max(renderHeight, 0))
    }
    
    private func renderedContentView(width: CGFloat, height: CGFloat) -> some View {
        return ZStack {
            Image(nsImage: originalImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
            
            // Drawing overlay
            Canvas { context, size in
                // Draw paths
                for path in paths {
                    var p = Path()
                    guard let first = path.points.first else { continue }
                    p.move(to: first)
                    for point in path.points.dropFirst() {
                        p.addLine(to: point)
                    }
                    context.stroke(p, with: .color(.red), lineWidth: 4)
                }
                
                if let current = currentPath {
                    var p = Path()
                    guard let first = current.points.first else { return }
                    p.move(to: first)
                    for point in current.points.dropFirst() {
                        p.addLine(to: point)
                    }
                    context.stroke(p, with: .color(.red), lineWidth: 4)
                }
                
                // Draw blur/redact regions as black rectangles with pattern
                for region in blurRegions {
                    let rect = region.rect
                    // Solid dark fill for redaction
                    context.fill(Path(rect), with: .color(Color.black))
                    // Subtle pattern to indicate redaction
                    context.stroke(Path(rect), with: .color(Color.gray.opacity(0.5)), lineWidth: 1)
                    
                    // Draw diagonal lines pattern
                    let step: CGFloat = 8
                    var patternPath = Path()
                    var x = rect.minX
                    while x < rect.maxX {
                        patternPath.move(to: CGPoint(x: x, y: rect.minY))
                        patternPath.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
                        x += step
                    }
                    context.stroke(patternPath, with: .color(Color.gray.opacity(0.15)), lineWidth: 0.5)
                }
                
                // Draw current blur region being dragged
                if let currentRect = currentBlurRect {
                    context.fill(Path(currentRect), with: .color(Color.black.opacity(0.7)))
                    context.stroke(Path(currentRect), with: .color(Color.red.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [4]))
                }
            }
        }
        .frame(width: width, height: height)
    }
    
    private func interactionLayer(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Dark overlay for crop
            if let crop = cropRect, mode == .crop {
                Path { path in
                    path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
                    path.addRect(crop)
                }
                .fill(style: FillStyle(eoFill: true))
                .foregroundColor(Color.black.opacity(0.5))
                
                // Crop border
                Rectangle()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
            } else if mode == .crop && !isDraggingCrop {
                Color.black.opacity(0.1)
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if mode == .draw {
                        if currentPath == nil {
                            currentPath = DrawingPath(points: [value.location])
                        } else {
                            currentPath?.points.append(value.location)
                        }
                    } else if mode == .crop {
                        if !isDraggingCrop {
                            dragStartPoint = value.location
                            isDraggingCrop = true
                        }
                        let x = min(dragStartPoint.x, value.location.x)
                        let y = min(dragStartPoint.y, value.location.y)
                        let w = abs(dragStartPoint.x - value.location.x)
                        let h = abs(dragStartPoint.y - value.location.y)
                        cropRect = CGRect(x: x, y: y, width: w, height: h)
                    } else if mode == .blur {
                        if currentBlurStart == nil {
                            currentBlurStart = value.location
                        }
                        let start = currentBlurStart!
                        let x = min(start.x, value.location.x)
                        let y = min(start.y, value.location.y)
                        let w = abs(start.x - value.location.x)
                        let h = abs(start.y - value.location.y)
                        currentBlurRect = CGRect(x: x, y: y, width: w, height: h)
                    }
                }
                .onEnded { value in
                    if mode == .draw {
                        if let path = currentPath {
                            paths.append(path)
                        }
                        currentPath = nil
                    } else if mode == .crop {
                        isDraggingCrop = false
                    } else if mode == .blur {
                        if let rect = currentBlurRect, rect.width > 4 && rect.height > 4 {
                            blurRegions.append(BlurRegion(rect: rect))
                        }
                        currentBlurStart = nil
                        currentBlurRect = nil
                    }
                }
        )
    }
    
    @MainActor
    private func finishEditing() {
        // 1. Render the image + drawings
        let aspect = originalImage.size.width / originalImage.size.height
        let viewAspect = viewSize.width / viewSize.height
        
        var renderWidth: CGFloat
        var renderHeight: CGFloat
        
        if aspect > viewAspect {
            renderWidth = viewSize.width
            renderHeight = viewSize.width / aspect
        } else {
            renderHeight = viewSize.height
            renderWidth = viewSize.height * aspect
        }
        
        let renderer = ImageRenderer(content: renderedContentView(width: renderWidth, height: renderHeight))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        guard let nsImage = renderer.nsImage else {
            onComplete(nil)
            return
        }
        
        // 2. Crop if needed
        var finalImage = nsImage
        if mode == .crop, let crop = cropRect {
            // Because interactionLayer exactly matches renderedContentView size,
            var rect = NSRect(x: 0, y: 0, width: nsImage.size.width, height: nsImage.size.height)
            if let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil as NSGraphicsContext?, hints: nil as [NSImageRep.HintKey: Any]?) {
                // SwiftUI coordinate system vs CGImage coordinate system
                // SwiftUI Y is down. CGImage Y is down if from NSImage? Actually NSImage Y is UP.
                // Let's flip Y for CGImage cropping
                let flippedY = CGFloat(cgImage.height) - (crop.origin.y * renderer.scale) - (crop.height * renderer.scale)
                
                let cgCropRect = CGRect(
                    x: crop.origin.x * renderer.scale,
                    y: flippedY,
                    width: crop.width * renderer.scale,
                    height: crop.height * renderer.scale
                )
                
                if let croppedCG = cgImage.cropping(to: cgCropRect) {
                    finalImage = NSImage(cgImage: croppedCG, size: NSSize(width: crop.width, height: crop.height))
                }
            }
        }
        
        // 3. Convert to JPEG Data
        if let tiff = finalImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpeg = bitmap.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: NSNumber(value: 0.8)]) {
            onComplete(jpeg)
        } else {
            onComplete(nil)
        }
    }
}
