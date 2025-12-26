import SwiftUI

struct EqualiserView: View {
    @ObservedObject var playerManager: AudioPlayerManager
    @Environment(\.presentationMode) var presentationMode
    
    // We use a local state for smooth dragging, commit to engine on change
    @State private var gains: [Float] = [0, 0, 0, 0, 0, 0]
    
    @State private var currentPresetName: String? = nil
    
    // Frequencies for display labels (Simplified)
    let freqLabels = ["60", "170", "310", "600", "3k", "14k"]
    
    // Range for Gain (-12dB to +12dB)
    let maxGain: Float = 12.0
    let minGain: Float = -12.0
    
    struct EQPreset: Identifiable {
        let id = UUID()
        let name: String
        let gains: [Float]
    }
    
    let presets: [EQPreset] = [
        EQPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Boost", gains: [6, 4, 2, 0, 0, 0]),
        EQPreset(name: "Rock", gains: [4, 3, -1, 1, 3, 4]),
        EQPreset(name: "Pop", gains: [3, 1, 0, 2, 4, 3]),
        EQPreset(name: "Vocal", gains: [-2, -1, 3, 5, 4, 2]),
        EQPreset(name: "Treble", gains: [0, 0, 0, 3, 5, 6]),
        EQPreset(name: "Jazz", gains: [3, 2, 0, 2, 1, 4])
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    
                    // Header Area removed in favor of Navigation Title
                    Spacer().frame(height: 10)
                    
                    // EQ Visualization & Interaction Area
                    GeometryReader { geometry in
                        ZStack {
                            // 1. Grid Background
                            EQGrid(geometry: geometry)
                            
                            // 2. The Curve Fill (Gradient)
                            EQShape(gains: gains)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.offlineOrange.opacity(0.6), Color.offlineOrange.opacity(0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .mask(
                                     // Mask to only show below the curve? 
                                     // Actually EQShape closes at bottom, so fill works naturally.
                                     Rectangle()
                                )
                            
                            // 3. The Curve Stroke
                            EQShape(gains: gains)
                                .stroke(Color.white, lineWidth: 2)
                                .shadow(color: .white.opacity(0.5), radius: 4)
                            
                            // 4. Control Points (Draggable)
                            ForEach(0..<gains.count, id: \.self) { index in
                                ControlPoint(
                                    index: index,
                                    count: gains.count,
                                    gain: $gains[index],
                                    geometry: geometry,
                                    minGain: minGain,
                                    maxGain: maxGain,
                                    onChanged: {
                                        updateEngine()
                                    }
                                )
                            }
                        }
                    }
                    .frame(height: 300)
                    .background(Color.offlineDarkGray.opacity(0.3))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding()
                    
                    // Frequency Labels
                    HStack {
                        ForEach(freqLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Presets Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(presets) { preset in
                                Button(action: {
                                    withAnimation(.spring()) {
                                        self.gains = preset.gains
                                    }
                                    updateEngine()
                                }) {
                                    Text(preset.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(currentPresetName == preset.name ? Color.offlineOrange : Color.offlineDarkGray)
                                        .foregroundColor(.white)
                                        .cornerRadius(20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 10)
                    

                    
                    Spacer()
                    
                    // Bottom Actions
                    HStack(spacing: 40) {
                        Button(action: {
                            resetEQ()
                        }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Flat")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.offlineDarkGray)
                            .cornerRadius(25)
                        }
                        
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Done")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.offlineOrange)
                            .cornerRadius(25)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Equaliser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                self.gains = playerManager.getCurrentEQGains()
                updateActivePreset()
            }
            // Use onChange(of: gains) for iOS 17+
            .onChange(of: gains) {
                updateActivePreset()
            }
        }
    }
    
    private func updateEngine() {
        playerManager.updateEQ(gains: gains)
        // updateActivePreset() // Triggered by onChange
    }
    
    private func resetEQ() {
        withAnimation(.spring()) {
            gains = [Float](repeating: 0.0, count: gains.count)
        }
        playerManager.resetEQ()
    }
    
    private func updateActivePreset() {
        // Simple exact match check logic moved here
        for preset in presets {
            // Fuzzy match for floats
            let diff = zip(gains, preset.gains).map { abs($0 - $1) }.reduce(0, +)
            if diff < 0.1 { 
                currentPresetName = preset.name 
                return
            }
        }
        currentPresetName = nil
    }
}

// MARK: - Shapes & Helpers

struct EQGrid: View {
    let geometry: GeometryProxy
    
    var body: some View {
        Path { path in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Horizontal lines (dB)
            // 0 dB (Center)
            path.move(to: CGPoint(x: 0, y: height / 2))
            path.addLine(to: CGPoint(x: width, y: height / 2))
            
            // +6 dB (25%)
            path.move(to: CGPoint(x: 0, y: height * 0.25))
            path.addLine(to: CGPoint(x: width, y: height * 0.25))
            
            // -6 dB (75%)
            path.move(to: CGPoint(x: 0, y: height * 0.75))
            path.addLine(to: CGPoint(x: width, y: height * 0.75))
            
            // Vertical lines (Freq)
            let step = width / CGFloat(6)
            for i in 0...5 {
                let x = step * CGFloat(i) + (step / 2)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }
        }
        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
    }
}

struct AnimatableVector: VectorArithmetic {
    var values: [Float]
    
    static var zero: AnimatableVector {
        return AnimatableVector(values: [])
    }
    
    var magnitudeSquared: Double {
        return values.reduce(0) { $0 + Double($1 * $1) }
    }
    
    mutating func scale(by rhs: Double) {
        values = values.map { $0 * Float(rhs) }
    }
    
    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        let count = min(lhs.values.count, rhs.values.count)
        var result: [Float] = []
        for i in 0..<count {
            result.append(lhs.values[i] - rhs.values[i])
        }
        return AnimatableVector(values: result)
    }
    
    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        let count = min(lhs.values.count, rhs.values.count)
        var result: [Float] = []
        for i in 0..<count {
            result.append(lhs.values[i] + rhs.values[i])
        }
        return AnimatableVector(values: result)
    }
}

struct EQShape: Shape {
    var gains: [Float]
    // Removed geometry: GeometryProxy (Error fix)
    
    // Animate path changes
    var animatableData: AnimatableVector {
        get { AnimatableVector(values: gains) }
        set { gains = newValue.values }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let count = gains.count
        guard count > 0 else { return path }
        
        let step = width / CGFloat(count)
        
        // Helper to convert gain (-12...12) to Y (height...0)
        func yForGain(_ gain: Float) -> CGFloat {
             // Map -12..12 to 1..0 (Height..0)
             let normalized = CGFloat((gain + 12) / 24)
             return height * (1 - normalized)
        }
        
        // Start bottom left
        path.move(to: CGPoint(x: 0, y: height))
        
        // Loop points
        var points: [CGPoint] = []
        for i in 0..<count {
            let x = step * CGFloat(i) + (step / 2)
            let y = yForGain(gains[i])
            points.append(CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: 0, y: points.first?.y ?? height/2))
        
        if points.count >= 2 {
             // Redraw curve part
             path = Path()
             path.move(to: CGPoint(x: 0, y: height)) // Bottom Left
             path.addLine(to: CGPoint(x: 0, y: yForGain(gains[0]))) // Go up to first point
             
             path.addLine(to: points[0])
             for i in 0..<points.count-1 {
                 let thisP = points[i]
                 let nextP = points[i+1]
                 let control1 = CGPoint(x: thisP.x + (nextP.x - thisP.x)/2, y: thisP.y)
                 let control2 = CGPoint(x: thisP.x + (nextP.x - thisP.x)/2, y: nextP.y)
                 path.addCurve(to: nextP, control1: control1, control2: control2)
             }
        }
        
        // Finish to Right Edge
        path.addLine(to: CGPoint(x: width, y: points.last?.y ?? height/2))
        path.addLine(to: CGPoint(x: width, y: height)) // Bottom Right
        path.closeSubpath()
        
        return path
    }
}


struct ControlPoint: View {
    let index: Int
    let count: Int
    @Binding var gain: Float
    let geometry: GeometryProxy
    let minGain: Float
    let maxGain: Float
    let onChanged: () -> Void
    
    var body: some View {
        let width = geometry.size.width
        let height = geometry.size.height
        let step = width / CGFloat(count)
        let x = step * CGFloat(index) + (step / 2)
        
        // Y Position
        // Map 12 -> 0, -12 -> height
        let normalized = CGFloat( (gain - minGain) / (maxGain - minGain) )
        // normalized is 0 at min, 1 at max.
        // We want Y: 0 at max, Height at min
        let y = height * (1 - normalized)
        
        Circle()
            .fill(Color.white)
            .frame(width: 20, height: 20) // The Dot
            .shadow(radius: 2)
            .position(x: x, y: y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let locationY = value.location.y
                        // Clamp Y
                        let clampedY = min(max(0, locationY), height)
                        
                        // Convert back to Gain
                        // clampedY / height = 1 - normalized
                        // normalized = 1 - (clampedY / height)
                        let newNorm = 1 - (clampedY / height)
                        let newGain = Float(newNorm) * (maxGain - minGain) + minGain
                        
                        self.gain = newGain
                        onChanged()
                    }
            )
    }
}
