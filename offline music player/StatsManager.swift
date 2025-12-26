import Foundation
import SwiftUI
import Combine

class StatsManager: ObservableObject {
    static let shared = StatsManager()
    
    // Key: Song URL Path -> Seconds Listened
    @Published var songStats: [String: TimeInterval] = [:]
    
    private let statsKey = "user_listening_stats"
    
    private init() {
        restoreStats()
    }
    
    // MARK: - Logging
    
    func logListen(song: Song, seconds: Double) {
        let path = song.url.path
        songStats[path, default: 0] += seconds
        
        // Debounce saving if needed, but for now we'll save on significant updates or app backgrounding.
        // For simplicity and robustness, specific save checkpoints can be added. 
        // But to avoid hitting UserDefaults every 0.5s, we can setup a throttled saver or just save on app state changes.
        // For this implementation, we will rely on a periodic save or on-terminate save, 
        // BUT user wanted "real time" feel? 
        // Let's debounce the UserDefaults write but keep the memory up to date.
        debounceSave()
    }
    
    private var saveTask: Task<Void, Error>?
    
    private func debounceSave() {
        saveTask?.cancel()
        saveTask = Task {
            try await Task.sleep(nanoseconds: 5_000_000_000) // Save every 5 seconds of inactivity/accumulation
            await MainActor.run {
                self.saveStats()
            }
        }
    }
    
    func forceSave() {
        saveStats()
    }
    
    func refresh() {
        restoreStats()
        objectWillChange.send() // Ensure UI updates
    }
    
    // MARK: - Persistence
    
    private func saveStats() {
        UserDefaults.standard.set(songStats, forKey: statsKey)
    }
    
    private func restoreStats() {
        if let data = UserDefaults.standard.dictionary(forKey: statsKey) as? [String: TimeInterval] {
            songStats = data
        }
    }
    
    // MARK: - Aggregators
    
    func getDuration(for song: Song) -> TimeInterval {
        return songStats[song.url.path] ?? 0
    }
    
    func getDuration(forArtist artistName: String, allSongs: [Song]) -> TimeInterval {
        let artistSongs = allSongs.filter { $0.artist == artistName }
        return artistSongs.reduce(0) { $0 + getDuration(for: $1) }
    }
    
    func getDuration(forAlbum albumName: String, allSongs: [Song]) -> TimeInterval {
        let albumSongs = allSongs.filter { $0.album == albumName }
        return albumSongs.reduce(0) { $0 + getDuration(for: $1) }
    }
    
    func getDuration(forPlaylist playlist: Playlist, allSongs: [Song], pathMap: [String: Song]? = nil) -> TimeInterval {
        // Optimization: if a pathMap is provided, use it. Else search.
        var total: TimeInterval = 0
        for path in playlist.songPaths {
            total += songStats[path] ?? 0
        }
        return total
    }
    
    func getTotalListeningTime() -> TimeInterval {
        return songStats.values.reduce(0, +)
    }
    
    func formattedTime(_ totalSeconds: TimeInterval) -> String {
        if totalSeconds == 0 { return "-" }
        
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    // MARK: - Top Lists
    
    func getTopSongs(allSongs: [Song], count: Int = 3) -> [(song: Song, duration: TimeInterval)] {
        // Map songs to duration, sort desc
        let mapped = allSongs.map { ($0, getDuration(for: $0)) }
                             .filter { $0.1 > 0 }
        let sorted = mapped.sorted { $0.1 > $1.1 }
        return Array(sorted.prefix(count))
    }
    
    func getTopArtists(allSongs: [Song], count: Int = 3) -> [(name: String, duration: TimeInterval)] {
        let artists = Set(allSongs.map { $0.artist })
        let mapped = artists.map { ($0, getDuration(forArtist: $0, allSongs: allSongs)) }
                            .filter { $0.1 > 0 }
        let sorted = mapped.sorted { $0.1 > $1.1 }
        return Array(sorted.prefix(count))
    }
    
    func getTopAlbums(allSongs: [Song], count: Int = 3) -> [(name: String, duration: TimeInterval)] {
        let albums = Set(allSongs.map { $0.album })
        let mapped = albums.map { ($0, getDuration(forAlbum: $0, allSongs: allSongs)) }
                           .filter { $0.1 > 0 }
        let sorted = mapped.sorted { $0.1 > $1.1 }
        return Array(sorted.prefix(count))
    }
    
    func getTopPlaylists(playlists: [Playlist], allSongs: [Song], count: Int = 3) -> [(playlist: Playlist, duration: TimeInterval)] {
        let mapped = playlists.map { ($0, getDuration(forPlaylist: $0, allSongs: allSongs)) }
                              .filter { $0.1 > 0 }
        let sorted = mapped.sorted { $0.1 > $1.1 }
        return Array(sorted.prefix(count))
    }
}
