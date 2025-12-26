import SwiftUI

struct PieChartView: View {
    let items: [(name: String, value: Double)]
    
    var body: some View {
        VStack {
            if items.isEmpty {
                Text("Not enough data")
                    .foregroundColor(.gray)
                    .font(.caption)
            } else {
                ZStack {
                    ForEach(0..<slices.count, id: \.self) { index in
                        PieSliceView(
                            startAngle: .degrees(slices[index].startAngle),
                            endAngle: .degrees(slices[index].endAngle),
                            color: colors[index % colors.count]
                        )
                    }
                    
                    // Center hole for donut look (optional, but looks "premium")
                    Circle()
                        .fill(Color.offlineBackground)
                        .frame(width: 100, height: 100)
                    
                    VStack {
                        Text("Top Artists")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 200)
                .padding(.vertical)
                
                // Legend
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<min(items.count, 5), id: \.self) { index in
                        HStack {
                            Circle()
                                .fill(colors[index % colors.count])
                                .frame(width: 10, height: 10)
                            Text(items[index].name)
                                .font(.caption)
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.0f%%", (items[index].value / totalValue) * 100))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color.offlineDarkGray)
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Calculation Helpers
    
    private var totalValue: Double {
        items.reduce(0) { $0 + $1.value }
    }
    
    private struct SliceData {
        var startAngle: Double
        var endAngle: Double
    }
    
    private var slices: [SliceData] {
        var result: [SliceData] = []
        var currentAngle: Double = -90 // Start at top
        
        for item in items {
            let angle = (item.value / totalValue) * 360
            result.append(SliceData(startAngle: currentAngle, endAngle: currentAngle + angle))
            currentAngle += angle
        }
        return result
    }
    
    private let colors: [Color] = [.offlineOrange, .blue, .purple, .pink, .green, .yellow, .red, .teal]
}

struct PieSliceView: View {
    var startAngle: Angle
    var endAngle: Angle
    var color: Color
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = min(geometry.size.width, geometry.size.height)
                let height = width
                let center = CGPoint(x: width * 0.5, y: height * 0.5)
                
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: width * 0.5,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
            }
            .fill(color)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct SegmentationBar: View {
    let total: Double
    let segments: [(value: Double, color: Color)]
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Top Segments
                ForEach(0..<segments.count, id: \.self) { index in
                    let width = (segments[index].value / total) * geo.size.width
                    if width > 0 {
                        Rectangle()
                            .fill(segments[index].color)
                            .frame(width: width)
                    }
                }
                
                // "Other" Segment
                let usedTotal = segments.reduce(0) { $0 + $1.value }
                let remaining = max(0, total - usedTotal)
                let remainingWidth = (remaining / total) * geo.size.width
                
                if remainingWidth > 0 {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3)) // Distinct grey for 'Other'
                        .frame(width: remainingWidth)
                }
            }
        }
        .frame(height: 8)
        .cornerRadius(4)
        .clipped()
    }
}
