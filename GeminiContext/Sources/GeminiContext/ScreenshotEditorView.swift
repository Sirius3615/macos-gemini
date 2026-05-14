import SwiftUI

struct DrawingPath: Identifiable {
    let id = UUID()
    var points: [CGPoint]
}

struct ScreenshotEditorView: View {
    let originalImage: NSImage
    let onComplete: (Data?) -> Void
    
    @State private var mode: EditMode = .crop
    @State private var paths: [DrawingPath] = []
    @State private var currentPath: DrawingPath?
    
    // Crop state
    @State private var cropRect: CGRect?
    @State private var isDraggingCrop = false
    @State private var dragStartPoint: CGPoint = .zero
    
    // Geometry for rendering
    @State private var viewSize: CGSize = .zero
    
    enum EditMode {
        case draw
        case crop
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
                    Text("Crop").tag(EditMode.crop)
                    Text("Draw").tag(EditMode.draw)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                
                Spacer()
                
                Button("Done") {
                    finishEditing()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            
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
