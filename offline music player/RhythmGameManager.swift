import SwiftUI
import AVFoundation
import Combine

/// Represents a tile on screen
struct GameTile: Identifiable {
    let id = UUID()
    let beat: Beat
    var yPosition: CGFloat = 0 // 0 = top, 1 = tap zone
    var isHit: Bool = false
    var isMissed: Bool = false
}

/// Hit accuracy levels
enum HitAccuracy {
    case perfect // ±50ms
    case good    // ±100ms
    case miss
    
    var points: Int {
        switch self {
        case .perfect: return 100
        case .good: return 50
        case .miss: return 0
        }
    }
    
    var color: Color {
        switch self {
        case .perfect: return .yellow
        case .good: return .green
        case .miss: return .red
        }
    }
}

/// Game state
enum GameState {
    case selectingSong
    case loading
    case playing
    case paused
    case finished
}

/// Manages the rhythm game state and logic
class RhythmGameManager: ObservableObject {
    @Published var state: GameState = .selectingSong
    @Published var selectedSong: Song?

    @Published var beats: [Beat] = []
    @Published var allBeats: [Difficulty: [Beat]] = [:]
    @Published var selectedDifficulty: Difficulty = .medium
    @Published var activeTiles: [GameTile] = []
    @Published var score: Int = 0
    @Published var combo: Int = 0
    @Published var maxCombo: Int = 0
    @Published var perfectHits: Int = 0
    @Published var goodHits: Int = 0
    @Published var misses: Int = 0
    @Published var loadingProgress: Double = 0
    @Published var lastHitAccuracy: HitAccuracy?
    
    private var audioPlayer: AVAudioPlayer?
    private var gameTimer: Timer?
    private var startTime: Date?
    private var currentBeatIndex: Int = 0
    
    // Timing constants
    let tileSpawnLeadTime: TimeInterval = 2.0 // Tiles appear 2 seconds before hit time
    let tapZonePosition: CGFloat = 0.92 // 92% down the screen
    let perfectWindow: TimeInterval = 0.05 // ±50ms
    let goodWindow: TimeInterval = 0.10 // ±100ms
    
    // Lane colors
    let laneColors: [Color] = [.red, .yellow, .green, .blue]
    
    func selectSong(_ song: Song) {
        selectedSong = song
        state = .loading
        loadingProgress = 0
        
        Task {
            await loadAndAnalyzeSong(song)
        }
    }
    
    private func loadAndAnalyzeSong(_ song: Song) async {
        do {
            // Check Cache first
            if let cachedBeats = BeatDetector.loadFromCache(songId: song.id) {
                print("Loaded from cache!")
                await MainActor.run { loadingProgress = 1.0 }
                // Use cached data
                await MainActor.run {
                    self.allBeats = cachedBeats
                }
            } else {
                // Not in cache, simulate progress and detect
                await MainActor.run { loadingProgress = 0.2 }
                
                // Detect beats
                let detectedBeats = try await BeatDetector.detectBeats(from: song.url)
                
                // Save to cache
                BeatDetector.saveToCache(beats: detectedBeats, songId: song.id)
                
                await MainActor.run {
                    self.allBeats = detectedBeats
                    loadingProgress = 0.8
                }
            }
            
            // Prepare audio player
            let accessing = song.url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    song.url.stopAccessingSecurityScopedResource()
                }
            }
            
            let player = try AVAudioPlayer(contentsOf: song.url)
            player.prepareToPlay()
            
            await MainActor.run {
                // self.allBeats is already set above
                self.audioPlayer = player
                self.loadingProgress = 1.0
                
                // Auto-start using default (medium)
                self.startGame(difficulty: .medium)
            }
        } catch {
            await MainActor.run {
                print("Error loading song: \(error)")
                self.state = .selectingSong
            }
        }
    }
    
    func startGame(difficulty: Difficulty? = nil) {
        if let difficulty = difficulty {
            self.selectedDifficulty = difficulty
        }
        
        // Load beats for selected difficulty
        self.beats = self.allBeats[self.selectedDifficulty] ?? []
        
        score = 0
        combo = 0
        maxCombo = 0
        perfectHits = 0
        goodHits = 0
        misses = 0
        currentBeatIndex = 0
        activeTiles = []
        
        state = .playing
        
        // Add 3 second delay for preparation
        let startDelay: TimeInterval = 3.0
        startTime = Date().addingTimeInterval(startDelay)
        
        audioPlayer?.currentTime = 0
        audioPlayer?.play(atTime: audioPlayer!.deviceCurrentTime + startDelay)
        
        // Game loop at 60fps
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateGame()
        }
    }
    
    private func updateGame() {
        guard let startTime = startTime, state == .playing else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Spawn new tiles
        while currentBeatIndex < beats.count {
            let beat = beats[currentBeatIndex]
            // Spawn tile when it's time (lead time before hit)
            if beat.time - tileSpawnLeadTime <= elapsed {
                let tile = GameTile(beat: beat)
                activeTiles.append(tile)
                currentBeatIndex += 1
            } else {
                break
            }
        }
        
        // Update tile positions
        for i in activeTiles.indices {
            let tile = activeTiles[i]
            let timeSinceSpawn = elapsed - (tile.beat.time - tileSpawnLeadTime)
            let progress = timeSinceSpawn / tileSpawnLeadTime
            activeTiles[i].yPosition = CGFloat(progress) * tapZonePosition
            
            // Check for missed tiles
            if elapsed > tile.beat.time + goodWindow && !tile.isHit && !tile.isMissed {
                activeTiles[i].isMissed = true
                registerMiss()
            }
        }
        
        // Remove old tiles
        activeTiles.removeAll { $0.yPosition > 1.2 }
        
        // Check if song is finished
        if let player = audioPlayer, !player.isPlaying && elapsed > 1.0 {
            endGame()
        }
    }
    
    func tapLane(_ lane: Int) {
        guard state == .playing, let startTime = startTime else { return }
        
        let tapTime = Date().timeIntervalSince(startTime)
        
        // Find closest unhit tile in this lane
        var closestIndex: Int?
        var closestDiff: TimeInterval = .infinity
        
        for (index, tile) in activeTiles.enumerated() {
            if tile.beat.lane == lane && !tile.isHit && !tile.isMissed {
                let diff = abs(tapTime - tile.beat.time)
                if diff < closestDiff {
                    closestDiff = diff
                    closestIndex = index
                }
            }
        }
        
        // Evaluate hit
        if let index = closestIndex {
            if closestDiff <= perfectWindow {
                registerHit(index: index, accuracy: .perfect)
            } else if closestDiff <= goodWindow {
                registerHit(index: index, accuracy: .good)
            }
            // Outside window = ignore tap (don't penalize)
        }
    }
    
    private func registerHit(index: Int, accuracy: HitAccuracy) {
        activeTiles[index].isHit = true
        combo += 1
        maxCombo = max(maxCombo, combo)
        score += accuracy.points * max(1, combo / 10 + 1)
        lastHitAccuracy = accuracy
        
        switch accuracy {
        case .perfect: perfectHits += 1
        case .good: goodHits += 1
        case .miss: break
        }
        
        // Clear feedback after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if self?.lastHitAccuracy == accuracy {
                self?.lastHitAccuracy = nil
            }
        }
    }
    
    private func registerMiss() {
        combo = 0
        misses += 1
        lastHitAccuracy = .miss
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if self?.lastHitAccuracy == .miss {
                self?.lastHitAccuracy = nil
            }
        }
    }
    
    func endGame() {
        state = .finished
        gameTimer?.invalidate()
        gameTimer = nil
        audioPlayer?.stop()
    }
    
    func retry() {
        startGame() // Reuses selected difficulty
    }
    
    func exit() {
        gameTimer?.invalidate()
        gameTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayer = nil
        beats = []
        allBeats = [:]
        activeTiles = []
        selectedSong = nil
        state = .selectingSong
    }
}
