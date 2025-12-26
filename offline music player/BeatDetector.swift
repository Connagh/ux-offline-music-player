import AVFoundation
import Accelerate

/// Game difficulty levels
enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case easy
    case medium
    case hard
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }
    
    var color: String { // Hex codes for now, or use system colors in View
        return "#FFCC00"
    }
}

/// A beat detected in the audio
struct Beat: Identifiable, Codable {
    var id = UUID()
    let time: TimeInterval
    let lane: Int
    let intensity: Float
}

/// Analyzes audio files to detect beats based on amplitude peaks
class BeatDetector {
    
    /// Analyze an audio file and return detected beats for all difficulties
    static func detectBeats(from url: URL) async throws -> [Difficulty: [Beat]] {
        return try await Task.detached(priority: .userInitiated) {
            // Access security scoped resource
            // Note: Since we are in a detached task, we need to be careful with file access capture.
            // URL is struct, so it's copied. Secure access needs to happen here.
            
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                throw BeatDetectorError.bufferCreationFailed
            }
            
            try audioFile.read(into: buffer)
            
            guard let floatData = buffer.floatChannelData else { throw BeatDetectorError.noAudioData }
            
            // 1. Convert to Mono
            let channelCount = Int(format.channelCount)
            var monoSamples = [Float](repeating: 0, count: Int(frameCount))
            
            for i in 0..<Int(frameCount) {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += floatData[channel][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
            
            // 2. Apply "FX Processing" (EQ Simulation)
            let emphasizedSamples = applyTransientProcessing(samples: monoSamples, sampleRate: format.sampleRate)
            
            // 3. Peak Detection
            let allPeaks = detectPeaks(samples: emphasizedSamples, sampleRate: format.sampleRate)
            
            // 4. Generate Difficulty Maps
            let duration = Double(frameCount) / format.sampleRate
            return generateDifficulties(from: allPeaks, duration: duration)
        }.value
    }
    
    // MARK: - Caching
    
    private static nonisolated func getCacheURL(for songId: UUID) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let cacheDir = appSupport.appendingPathComponent("RhythmGameCache")
        
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        return cacheDir.appendingPathComponent("\(songId.uuidString).json")
    }
    
    static func loadFromCache(songId: UUID) -> [Difficulty: [Beat]]? {
        guard let url = getCacheURL(for: songId) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Difficulty: [Beat]].self, from: data)
    }
    
    static func saveToCache(beats: [Difficulty: [Beat]], songId: UUID) {
        Task.detached(priority: .background) {
            guard let url = getCacheURL(for: songId) else { return }
            guard let data = try? JSONEncoder().encode(beats) else { return }
            try? data.write(to: url)
        }
    }
    
    /// Simulates a multi-band processing chain to highlight rhythmic elements
    private static nonisolated func applyTransientProcessing(samples: [Float], sampleRate: Double) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)
        
        // Simple IIR Low Pass Filter (approx 150Hz)
        // y[n] = x[n] + (y[n-1] - x[n]) * C
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2.0 * .pi * 150.0)
        let alpha = dt / (rc + dt)
        
        var lowPassVal: Float = 0
        
        // Simple difference based High-Pass simulation (detecting quick changes)
        // Just differentiating the signal works well for onset detection.
        
        for i in 0..<samples.count {
            let x = samples[i]
            
            // Low Pass
            lowPassVal = lowPassVal + (Float(alpha) * (x - lowPassVal))
            
            // High Frequency Content (Original - LowPass)
            let highContent = x - lowPassVal
            
            // Emphasize the "Kick" (LowPass) and the "Snap" (HighContent)
            // Weighting: Kicks are fundamental (1.0), Snares provide rhythm (0.8)
            output[i] = (abs(lowPassVal) * Float(1.2)) + (abs(highContent) * Float(0.8))
        }
        
        return output
    }
    
    private static nonisolated func detectPeaks(samples: [Float], sampleRate: Double) -> [Beat] {
        let chunkDuration: TimeInterval = 0.02 // 20ms resolution is standard for rhythm games
        let chunkSize = Int(sampleRate * chunkDuration)
        let chunkCount = samples.count / chunkSize
        
        var energies = [Float](repeating: 0, count: chunkCount)
        
        // RMS Energy of blocks
        for i in 0..<chunkCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            // Basic efficient sum
            var sum: Float = 0
            for j in start..<end {
                sum += samples[j] // samples are already abs/rectified in applyTransientProcessing
            }
            energies[i] = sum / Float(end - start)
        }
        
        // Adaptive Thresholding
        var beats: [Beat] = []
        let windowSize = 8 // Look 100ms-160ms around
        let multiplier: Float = 1.3 // Beat must be 1.3x local average
        
        for i in windowSize..<(chunkCount - windowSize) {
            let current = energies[i]
            
            var localSum: Float = 0
            for j in (i - windowSize)..<(i + windowSize) {
                localSum += energies[j]
            }
            let localAvg = localSum / Float(windowSize * 2)
            
            if current > localAvg * multiplier && current > 0.05 { // 0.05 min threshold
                // Found a candidate
                // Check if it's the local maximum in a small neighborhood (3 frames)
                // This prevents double-triggers on wide peaks
                if current >= energies[i-1] && current >= energies[i+1] {
                    let time = Double(i) * chunkDuration
                    beats.append(Beat(time: time, lane: 0, intensity: current))
                }
            }
        }
        
        return beats
    }
    
    private static nonisolated func generateDifficulties(from rawBeats: [Beat], duration: TimeInterval) -> [Difficulty: [Beat]] {
        var result: [Difficulty: [Beat]] = [:]
        
        // Limit Removed: User requested removal of 100 tiles/60s cap.
        // We still filter by minInterval to prevent impossible stacking.
        
        let sortedBeats = rawBeats.sorted(by: { $0.time < $1.time })
        let filteredBeats = filterBeats(sortedBeats, minInterval: 0.15)
        
        result[.medium] = assignLanes(filteredBeats)
        
        // For compatibility with any old logic or future expansion, we can populate others or leave empty.
        // The manager will default to .medium.
        result[.easy] = result[.medium]
        result[.hard] = result[.medium]
        
        return result
    }
    
    private static nonisolated func filterBeats(_ beats: [Beat], minInterval: TimeInterval) -> [Beat] {
        var filtered: [Beat] = []
        var lastTime: TimeInterval = -minInterval
        
        // Input assumed sorted by time? No, rawBeats comes from sequential scan so it is time-sorted.
        // But if we filtered by candidates (medium/easy), we need to ensure time sort.
        let sortedInput = beats.sorted { $0.time < $1.time }
        
        for beat in sortedInput {
            if beat.time - lastTime >= minInterval {
                filtered.append(beat)
                lastTime = beat.time
            }
        }
        return filtered
    }
    
    private static nonisolated func assignLanes(_ beats: [Beat]) -> [Beat] {
        // Randomly assign lanes, but avoid same lane twice in a row if possible for flow?
        // Or just pure random 0-3.
        // Users like flow (0->1->2). Random is fine for a prototype.
        var assigned: [Beat] = []
        var lastLane = -1
        
        for beat in beats {
            var lane = Int.random(in: 0...3)
            // Simple logic: 50% chance to force a lane change if it's the same
            if lane == lastLane {
                if Bool.random() {
                    lane = (lane + 1) % 4
                }
            }
            assigned.append(Beat(time: beat.time, lane: lane, intensity: beat.intensity))
            lastLane = lane
        }
        return assigned
    }
}

enum BeatDetectorError: Error {
    case bufferCreationFailed
    case noAudioData
}
