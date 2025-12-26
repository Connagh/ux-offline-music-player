import SwiftUI
import UIKit

extension UIImage {
    func normalized() -> UIImage? {
        if self.imageOrientation == .up {
            // Even if orientation is correct, we apparently need to fix the pixel format for some files.
        }
        
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: self.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}

// MARK: - Colors & Theme
extension Color {
    static let offlineBackground = Color.black
    static let offlineDarkGray = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let offlineAccent = Color.white // Or a specific brand color if user wanted
    static let offlineOrange = Color(red: 1.0, green: 0.6, blue: 0.2) // For play button in design
}

// MARK: - Components

enum AudioQuality: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case max = "Max"
    
    static func from(song: Song) -> AudioQuality {
        // Max: Lossless && (BitDepth > 16 || SampleRate > 48000)
        // High: Lossless && (BitDepth <= 16 && SampleRate <= 48000)
        let rate = song.sampleRate ?? 0
        let depth = song.bitDepth ?? 0
        let bitrate = song.bitrate ?? 0
        
        if song.isLossless {
            if depth > 16 || rate > 48000 {
                return .max
            } else {
                return .high
            }
        } else {
            if bitrate >= 320_000 {
                return .medium
            } else {
                return .low
            }
        }
    }
}

struct HQBadge: View {
    let song: Song?
    let sampleRate: Double?
    
    init(song: Song) {
        self.song = song
        self.sampleRate = song.sampleRate
    }
    
    init(sampleRate: Double?) {
        self.song = nil
        self.sampleRate = sampleRate
    }
    
    var quality: AudioQuality? {
        if let s = song {
            return AudioQuality.from(song: s)
        }
        return nil
    }
    
    var labelText: String? {
        if let q = quality {
            return q.rawValue
        }
        guard let rate = sampleRate else { return nil }
        if rate > 48000 { return "Max" }
        return "High"
    }
    
    var body: some View {
        if let text = labelText {
            if text == "Max" {
                // Subtle Champagne Gold Gradient on White
                Text(text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                             // White to subtle gold tint
                             colors: [Color.white, Color(red: 1.0, green: 0.95, blue: 0.8)],
                             startPoint: .top,
                             endPoint: .bottom
                        )
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                             // Matching border
                            .stroke(
                                LinearGradient(
                                     colors: [Color.white, Color(red: 0.95, green: 0.9, blue: 0.6)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            } else {
                // Standard White Style (High/Medium/Low)
                Text(text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
            }
        }
    }
}

struct IconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Blur View (Glassmorphism)
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - Skeleton Loader
struct SkeletonRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 140, height: 16)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 12)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                 RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 30, height: 10)
            }
        }
        .padding(.vertical, 12)
        .opacity(isAnimating ? 0.3 : 0.7)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
