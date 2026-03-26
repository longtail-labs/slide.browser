import SwiftUI
import SlideDatabase

struct ImageView: View {
    let object: TaskObject
    @State private var zoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            if let filePath = object.filePath,
               let nsImage = NSImage(contentsOf: filePath) {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: geometry.size.width * zoomScale,
                            height: geometry.size.height * zoomScale
                        )
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = max(0.5, min(value, 5.0))
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .onAppear {
                    // Fit image to view initially
                    let size = nsImage.size
                    let widthRatio = geometry.size.width / size.width
                    let heightRatio = geometry.size.height / size.height
                    zoomScale = min(widthRatio, heightRatio, 1.0)
                }
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Image not found")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    if let path = object.filePath {
                        Text(path.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .overlay(alignment: .topTrailing) {
            // Zoom controls
            HStack(spacing: 8) {
                Button(action: { zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                
                Text("\(Int(zoomScale * 100))%")
                    .font(.caption)
                    .frame(width: 50)
                
                Button(action: { zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                
                Button(action: { resetZoom() }) {
                    Image(systemName: "1.magnifyingglass")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.regularMaterial)
            .cornerRadius(8)
            .padding()
        }
    }
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = min(zoomScale * 1.25, 5.0)
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(zoomScale * 0.8, 0.5)
        }
    }
    
    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
}