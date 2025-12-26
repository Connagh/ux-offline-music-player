import Foundation
import AVFoundation
import SwiftUI
import Combine



// MARK: - Models

struct Song: Identifiable, Hashable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let album: String
    let trackNumber: Int?
    let duration: TimeInterval
    
    // Normalized string for O(1) search filtering
    // Format: "title artist album" (lowercased, diacritic-insensitive)
    let searchIndex: String

    let artworkData: Data?
    let sampleRate: Double? // Audio sample rate in Hz
    let bitrate: Int? // Bits per second
    let bitDepth: Int? // Bits per sample
    let isLossless: Bool // True if format is lossless (ALAC, FLAC, PCM)
    let fileModificationDate: Date? // Track file mod date for cache validation
    
    // Helper to format duration
    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, url, title, artist, album, trackNumber, duration
        case searchIndex, artworkData, sampleRate, bitrate, bitDepth
        case isLossless, fileModificationDate
    }
    
    // MARK: - Equatable & Hashable
    static func == (lhs: Song, rhs: Song) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var songPaths: [String] // Persist using file paths
    var colorHex: String? // Custom color
    var iconEmoji: String? // [NEW] Custom emoji icon
    var coverArtData: Data? // [NEW] Custom cover image
    var createdAt: Date
    
    // MARK: - Customization Options
    static let availableColors: [String] = [
        // Classic
        "#FF5733", "#33FF57", "#3357FF", "#F333FF", "#FF3333",
        "#33FFF5", "#FF8C33", "#8C33FF", "#33FF8C", "#FF33A8",
        // Pastels
        "#FFB3BA", "#FFDFBA", "#FFFFBA", "#BAFFC9", "#BAE1FF",
        "#E6E6FA", "#FFC0CB", "#FFDAB9", "#E0FFFF", "#F0FFF0",
        // Darker Tones
        "#800000", "#008000", "#000080", "#808000", "#800080",
        "#008080", "#A52A2A", "#D2691E", "#5F9EA0", "#708090"
    ]
    
    static let availableEmojis: [String] = [
        // Music
        "🔥", "💿", "🎸", "🎧", "⭐️", "❤️", "🤘", "🎵", "🎶", "🎹",
        "🎤", "🥁", "🎺", "🎻", "🪕", "🎷", "📻", "🎙️", "🎚️", "🎛️",
        // Vibes / Moods
        "⚡️", "✨", "💫", "🌟", "🌙", "☀️", "☁️", "🌧️", "🌈", "🌊",
        "🏖️", "🏕️", "🏔️", "🏜️", "🏝️", "🌋", "🌌", "🌠", "🎇", "🎆",
        // Activities
        "🚗", "✈️", "🚀", "🚲", "🏃", "🏋️", "🧘", "🛀", "🛌", "🎉",
        "🍻", "🥂", "🍷", "🍹", "☕️", "🍵", "🥤", "🍿", "🎮", "📚",
        // Animals
        "🦁", "🐯", "🐻", "🐺", "🦊", "🐶", "🐱", "🐨", "🐼", "🐸",
        // Abstract
        "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "⚫️", "⚪️", "🟤", "💖"
    ]
}

struct FolderInfo: Identifiable, Codable {
    var id = UUID()
    let url: URL
    var songCount: Int
    var byteCount: Int64 = 0
    var isUbiquitous: Bool = false
    
    var sizeString: String {
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

// MARK: - Bookmark Manager (File Access)

// MARK: - Bookmark Manager (File Access)

class BookmarkManager: ObservableObject {
    @Published var songs: [Song] = []
    @Published var folders: [FolderInfo] = []
    struct LoadingState {
        var isActive: Bool = false
        var title: String = "Loading..."
    }
    
    @Published var isImporting = false
    @Published var loadingState = LoadingState()
    @Published var importedCount = 0
    @Published var playlists: [Playlist] = []
    @Published var likedPaths: Set<String> = []

    
    // Search
    @Published var searchText: String = ""
    @Published var filteredSongs: [Song] = []
    @Published var isFiltering: Bool = false
    
    @Published var processedBatchCount = 0
    @Published var totalBatchSize = 0
    
    private var activeScans = 0 {
        didSet {
            // No-op, managed via isImporting logic mostly
        }
    }
    
    private var allSearchMatches: [Song] = []
    private var cancellables = Set<AnyCancellable>()
    private let notebooksKey = "security_scoped_bookmarks_list"
    private let playlistsKey = "user_playlists_list"
    private let likesKey = "user_liked_paths"
    
    // Cache Management
    private let cacheVersion = 1
    private var cachedSongsDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let cacheDir = appSupport.appendingPathComponent("SongCache")
        
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        return cacheDir
    }

    
    var hasMoreSearchResults: Bool {
        return !searchText.isEmpty && filteredSongs.count < allSearchMatches.count
    }
    
    init() {
        restoreBookmarks()

        restorePlaylists()
        restoreLikes()
        setupSearchSubscription()
    }

    
    private func setupSearchSubscription() {
        // Combine publisher for search text and songs
        Publishers.CombineLatest($searchText, $songs)
            .handleEvents(receiveOutput: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isFiltering = true
                }
            })
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main) // Minimal debounce for Enter key
            .receive(on: DispatchQueue.global(qos: .userInitiated)) // Move strictly to background for work
            .sink { [weak self] (searchText, songs) in
                guard let self = self else { return }
                
                let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Pre-normalize query once
                let queryNormalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
                
                // Optimized: Filter FIRST using pre-computed index (O(N) * O(1))
                let matches = songs.filter { song in
                    if text.isEmpty { return true }
                    // Fast substring check against pre-normalized index
                    return song.searchIndex.contains(queryNormalized)
                }
                
                // Sort the filtered matches
                let sortedMatches = matches.sorted { 
                    let duration1 = StatsManager.shared.getDuration(for: $0)
                    let duration2 = StatsManager.shared.getDuration(for: $1)
                    
                    if duration1 == duration2 {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return duration1 > duration2
                }

                
                
                DispatchQueue.main.async {
                    self.allSearchMatches = sortedMatches
                    self.filteredSongs = sortedMatches
                    self.isFiltering = false
                }

            }
            .store(in: &cancellables)
    }
    
    func loadAllResults() {
        filteredSongs = allSearchMatches
    }
    
    // MARK: - Cache Management
    
    /// Save the songs array to disk cache
    private func saveSongsCache() {
        guard let cacheDir = cachedSongsDirectory else {
            Logger.shared.log("Failed to get cache directory", level: .error)
            return
        }
        
        // Capture songs on MainActor before detached task
        let songsToCache = self.songs
        let version = self.cacheVersion
        
        Task.detached(priority: .background) {
            let cacheURL = cacheDir.appendingPathComponent("songs_v\(version).json")
            
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(songsToCache)
                try data.write(to: cacheURL, options: .atomic)
                
                await MainActor.run {
                    Logger.shared.log("Saved \(songsToCache.count) songs to cache")
                }
            } catch {
                await MainActor.run {
                    Logger.shared.log("Failed to save songs cache: \(error)", level: .error)
                }
            }
        }
    }
    
    /// Load songs from disk cache
    private func loadSongsCache() -> [Song]? {
        guard let cacheDir = cachedSongsDirectory else { return nil }
        
        let cacheURL = cacheDir.appendingPathComponent("songs_v\(cacheVersion).json")
        
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            Logger.shared.log("No cache file found")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let songs = try decoder.decode([Song].self, from: data)
            Logger.shared.log("Loaded \(songs.count) songs from cache")
            return songs
        } catch {
            Logger.shared.log("Failed to load songs cache: \(error)", level: .error)
            return nil
        }
    }
    
    /// Validate cached songs - check if files still exist and haven't been modified
    private func validateCachedSongs(_ cachedSongs: [Song]) async -> [Song] {
        var validSongs: [Song] = []
        
        for song in cachedSongs {
            // Check if file still exists
            guard FileManager.default.fileExists(atPath: song.url.path) else {
                continue // File was deleted, skip it
            }
            
            // Check modification date if available
            if let cachedModDate = song.fileModificationDate {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: song.url.path)
                    if let currentModDate = attributes[.modificationDate] as? Date {
                        // If file was modified, skip it (will be re-scanned)
                        if currentModDate.timeIntervalSince(cachedModDate) > 1.0 {
                            continue
                        }
                    }
                } catch {
                    // If we can't get attributes, skip this song (will be re-scanned)
                    continue
                }
            }
            
            validSongs.append(song)
        }
        
        await MainActor.run {
            Logger.shared.log("Validated cache: \(validSongs.count) of \(cachedSongs.count) songs still valid")
        }
        
        return validSongs
    }
    
    /// Clear the songs cache (for manual reset)
    func clearSongsCache() {
        guard let cacheDir = cachedSongsDirectory else { return }
        let cacheURL = cacheDir.appendingPathComponent("songs_v\(cacheVersion).json")
        
        try? FileManager.default.removeItem(at: cacheURL)
        Logger.shared.log("Cleared songs cache")
    }

    
    // MARK: - iCloud Import Logic
    
    struct FolderAnalysis {
        let totalFiles: Int
        let cloudFiles: Int
        let cloudSize: Int64
        let url: URL
    }
    
    @Published var pendingImportAnalysis: FolderAnalysis?
    @Published var showImportAlert: Bool = false
    
    func analyzePendingFolder(url: URL) {
        Task {
            guard url.startAccessingSecurityScopedResource() else {
                 // Try accessing anyway if it's not security scoped (e.g. simulator sometimes)
                 return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            var totalCount = 0
            var cloudCount = 0
            var cloudSize: Int64 = 0
            
            let fileManager = FileManager.default
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .fileSizeKey, .totalFileAllocatedSizeKey]
            
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: options) {
                while let fileURL = enumerator.nextObject() as? URL {
                    do {
                        let values = try fileURL.resourceValues(forKeys: Set(keys))
                        
                        // Count audio files only
                         if self.isAudioFile(fileURL) {
                             totalCount += 1
                             
                             print("DEBUG: Analyzing \(fileURL.lastPathComponent)")
                             print("DEBUG: isUbiquitousItem: \(values.isUbiquitousItem ?? false)")
                             print("DEBUG: status: \(values.ubiquitousItemDownloadingStatus?.rawValue ?? "nil")")
                             
                             // Check for iCloud/CloudDocs
                             let isUbiquitous = values.isUbiquitousItem ?? false
                             let isCloudPath = fileURL.path.contains("CloudDocs") || fileURL.path.contains("Mobile Documents")
                             
                             if isUbiquitous || isCloudPath {
                                 var needsDownload = false
                                 
                                 // 1. Check official status
                                 if let status = values.ubiquitousItemDownloadingStatus {
                                     // Force prompt for CloudDocs path even if currently downloaded
                                     // User requests explicit import option for these folders
                                     if status != .current || isCloudPath {
                                         needsDownload = true
                                     }
                                 } else {
                                     // 2. Fallback: Check allocation size vs file size
                                     // If allocated size is tiny (< 4KB) but file size is large, it's likely a placeholder.
                                     let fileSize = Int64(values.fileSize ?? 0)
                                     let allocated = Int64(values.totalFileAllocatedSize ?? 0)
                                     
                                     // Only apply heuristic if file size is substantial (> 1MB) to avoid confusion with small text files
                                     if fileSize > 1_000_000 && allocated < 16_384 {
                                         needsDownload = true
                                     } else if isCloudPath {
                                         // If explicitly in cloud path and we rely on this warning, safer to assume it might need handling
                                         // But let's trust the heuristic or default to false if small?
                                         // User wants the prompt. Let's be aggressive if we detect CloudDocs.
                                         // But we don't want to block fully downloaded files thinking they are cloud.
                                         // If we can't confirm it's downloaded (no status), and it's in CloudDocs...
                                         // Let's assume 'needsDownload' if it's not clearly local.
                                         // For now, relying on status is best. if status is nil, it's weird.
                                     }
                                 }
                                 
                                 if needsDownload {
                                     print("DEBUG: Found cloud file! Path: \(fileURL.lastPathComponent)")
                                     cloudCount += 1
                                     cloudSize += Int64(values.fileSize ?? 0)
                                 }
                             }
                         }
                    } catch {
                        print("Error analyzing file: \(error)")
                    }
                }
            }
            
            let analysis = FolderAnalysis(totalFiles: totalCount, cloudFiles: cloudCount, cloudSize: cloudSize, url: url)
            
            await MainActor.run {
                if analysis.cloudFiles > 0 {
                    self.pendingImportAnalysis = analysis
                    self.showImportAlert = true
                } else {
                    // No cloud files, proceed directly
                    self.saveBookmark(for: url)
                }
            }
        }
    }
    
    func confirmImport() {
        guard let analysis = pendingImportAnalysis else { return }
        saveBookmark(for: analysis.url)
        pendingImportAnalysis = nil
        showImportAlert = false
    }
    
    func cancelImport() {
        pendingImportAnalysis = nil
        showImportAlert = false
    }

    func saveBookmark(for url: URL) {
        do {
            // Check if already imported
            if folders.contains(where: { $0.url == url }) { return }
            
            let isAccessing = url.startAccessingSecurityScopedResource()
            if !isAccessing {
                Logger.shared.log("Failed to access security scoped resource, attempting anyway...", level: .warning)
            }
            
            let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            
            // Append to existing bookmarks
            var currentBookmarks = UserDefaults.standard.array(forKey: notebooksKey) as? [Data] ?? []
            currentBookmarks.append(bookmarkData)
            UserDefaults.standard.set(currentBookmarks, forKey: notebooksKey)
            
            // Add to model and scan
            let newFolder = FolderInfo(url: url, songCount: 0)
            folders.append(newFolder)
            
            scanDirectory(for: newFolder, isUserInitiated: true)
            loadingState = LoadingState(isActive: true, title: "Importing Music...")

            Logger.shared.log("Attached new folder: \(url.lastPathComponent)")
            
        } catch {

            Logger.shared.log("Error saving bookmark: \(error)", level: .error)
            print("Error saving bookmark: \(error)")
        }
    }
    
    private func restoreBookmarks() {
        guard let bookmarks = UserDefaults.standard.array(forKey: notebooksKey) as? [Data] else { return }
        
        // Load cached songs first for instant library availability
        if let cachedSongs = loadSongsCache() {
            self.songs = cachedSongs
            self.importedCount = cachedSongs.count
            Logger.shared.log("Instantly loaded \(cachedSongs.count) songs from cache")
        }
        
        var updatedBookmarks = [Data]()
        var needsUpdate = false
        
        // Then restore folders and scan in background
        for data in bookmarks {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    Logger.shared.log("Found stale bookmark for \(url.lastPathComponent), attempting to renew...")
                    needsUpdate = true
                    if let newData = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        updatedBookmarks.append(newData)
                    } else {
                        updatedBookmarks.append(data) // Keep original if renewal fails
                    }
                } else {
                    updatedBookmarks.append(data)
                }
                
                if url.startAccessingSecurityScopedResource() {
                    let folder = FolderInfo(url: url, songCount: 0)
                    folders.append(folder)
                    scanDirectory(for: folder, isUserInitiated: false)
                }
            } catch {
                Logger.shared.log("Error restoring bookmark: \(error)", level: .error)
                print("Error restoring bookmark: \(error)")
            }
        }
        
        if needsUpdate {
             UserDefaults.standard.set(updatedBookmarks, forKey: notebooksKey)
             Logger.shared.log("Updated stale bookmarks")
        }
        
        if !folders.isEmpty {
            loadingState = LoadingState(isActive: true, title: "Loading Library...")
        }
        
        Logger.shared.log("Restored \(folders.count) folders")
    }
    
    func scanDirectory(for folder: FolderInfo, isUserInitiated: Bool = false, force: Bool = false) {
        // Reset counters if we are starting from 0 scans
        if activeScans == 0 {
            processedBatchCount = 0
            totalBatchSize = 0
        }
        activeScans += 1
        
        // Always show importing banner when scanning
        isImporting = true
        
        Logger.shared.log("Scanning directory: \(folder.url.path)")
        Task {
            let fileManager = FileManager.default
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            
            // Build cache lookup: path -> cached song
            var cacheMap: [String: Song] = [:]
            for song in self.songs {
                cacheMap[song.url.path] = song
            }
            
            var filesToProcess: [URL] = []
            var foundPaths: Set<String> = []
            var cachedCount = 0
            var totalSize: Int64 = 0
            var isFolderUbiquitous = false
            
            // PASS 1: Scan and Identify Work
            if let enumerator = fileManager.enumerator(at: folder.url, includingPropertiesForKeys: [.isRegularFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .contentModificationDateKey, .fileSizeKey], options: options) {
                while let fileURL = enumerator.nextObject() as? URL {
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .contentModificationDateKey, .fileSizeKey])
                        
                        // Force Download if needed
                        if resourceValues.isUbiquitousItem == true {
                             isFolderUbiquitous = true
                             if resourceValues.ubiquitousItemDownloadingStatus != .current {
                                 try? fileManager.startDownloadingUbiquitousItem(at: fileURL)
                             }
                        }
                        
                        if resourceValues.isRegularFile == true {
                             if self.isAudioFile(fileURL) {
                                 // Track size
                                 if let size = resourceValues.fileSize {
                                     totalSize += Int64(size)
                                 }
                                 
                                 let filePath = fileURL.path
                                 foundPaths.insert(filePath)
                                 
                                 // Check if in cache and modification date matches
                                 var shouldProcess = true
                                 if !force,
                                    let cachedSong = cacheMap[filePath],
                                    let cachedModDate = cachedSong.fileModificationDate,
                                    let currentModDate = resourceValues.contentModificationDate {
                                     // File hasn't changed, reuse cached data
                                     if abs(currentModDate.timeIntervalSince(cachedModDate)) <= 1.0 {
                                         shouldProcess = false
                                     }
                                 }
                                 
                                 if shouldProcess {
                                     filesToProcess.append(fileURL)
                                 } else {
                                     cachedCount += 1
                                 }
                             }
                         }
                    } catch {
                         // ignore errors
                    }
                }
            }
            
            // Update Totals on Main Thread
            await MainActor.run {
                // Update folder stats
                if let index = self.folders.firstIndex(where: { $0.id == folder.id }) {
                    self.folders[index].byteCount = totalSize
                    self.folders[index].isUbiquitous = isFolderUbiquitous
                }
                
                // Add *both* new and cached files to the total for correct "X of Y"
                self.totalBatchSize += (filesToProcess.count + cachedCount)
                
                // Immediately mark cached files as processed
                self.processedBatchCount += cachedCount
                
                // Ensure banner is on (redundant but safe)
                if !self.isImporting { self.isImporting = true }
            }
            
            // PASS 2: Process New/Modified Files
            var newSongs: [Song] = []
            
            for fileURL in filesToProcess {
                if let song = await self.processSong(url: fileURL) {
                    newSongs.append(song)
                    
                    await MainActor.run {
                        self.processedBatchCount += 1
                        self.importedCount += 1 // Legacy global count
                    }
                }
            }
            
            // Update Final State
            await MainActor.run {
                // Update imported count for this folder specifically
                if let index = self.folders.firstIndex(where: { $0.id == folder.id }) {
                    self.folders[index].songCount = foundPaths.count
                }
                
                // Remove songs from this folder that no longer exist
                let folderPath = folder.url.path
                self.songs.removeAll { song in
                    // If song is from this folder and not found in scan, remove it
                    song.url.path.hasPrefix(folderPath) && !foundPaths.contains(song.url.path)
                }
                
                // Add newly scanned songs
                // Add newly scanned songs (handle duplicates if forced)
                for newSong in newSongs {
                    if let idx = self.songs.firstIndex(where: { $0.url.path == newSong.url.path }) {
                        self.songs[idx] = newSong
                    } else {
                        self.songs.append(newSong)
                    }
                }
                
                // Sort all songs
                self.songs.sort { 
                    let duration1 = StatsManager.shared.getDuration(for: $0)
                    let duration2 = StatsManager.shared.getDuration(for: $1)
                    
                    if duration1 == duration2 {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return duration1 > duration2
                }
                
                Logger.shared.log("Finished scanning \(folder.url.lastPathComponent). Processed \(newSongs.count) new/modified songs.")
                
                // Decrement scan count
                self.activeScans -= 1
                if self.activeScans <= 0 {
                    self.activeScans = 0
                    self.isImporting = false
                    self.isImporting = false
                    self.loadingState = LoadingState(isActive: false)
                    
                    self.processedBatchCount = 0
                    self.totalBatchSize = 0
                    
                    // Save updated cache after all scans complete
                    self.saveSongsCache()
                }
            }

        }
    }
    
    func rescanAllFolders() {
        Logger.shared.log("Rescanning all folders...")
        loadingState = LoadingState(isActive: true, title: "Rescanning Library...")
        for folder in folders {
            scanDirectory(for: folder, isUserInitiated: true, force: true)
        }
    }
    
    func removeFolder(at offsets: IndexSet) {
        // Remove from folders list
        let foldersToRemove = offsets.map { folders[$0] }
        folders.remove(atOffsets: offsets)
        
        // Update UserDefaults
        // Note: We need to reconstruct the bookmarks list. simpler to just re-save valid ones or remove by URL matching?
        // Since we stored Raw Data, we can't easily match data -> URL without resolving.
        // But we have the URLs in `folders`. Re-serializing valid folders is cleaner.
        
        var newBookmarks: [Data] = []
        for folder in folders {
            do {
                if folder.url.startAccessingSecurityScopedResource() {
                     let data = try folder.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                     newBookmarks.append(data)
                     folder.url.stopAccessingSecurityScopedResource()
                }
            } catch {
                print("Error rewriting bookmark: \(error)")
            }
        }
        UserDefaults.standard.set(newBookmarks, forKey: notebooksKey)
        
        // Remove songs associated with these folders
        // We need to filter out songs whose URL string starts with the folder URL string
        // Or simply re-scan everything? Re-scanning is safest but slow.
        // Filtering is better.
        
        for folder in foldersToRemove {
            let FolderPath = folder.url.path
            songs.removeAll { song in
                song.url.path.hasPrefix(FolderPath)
            }
        }
    }
    
    func removeAll() {
        folders.removeAll()
        songs.removeAll()
        filteredSongs.removeAll()
        allSearchMatches.removeAll()
        playlists.removeAll()
        importedCount = 0
        
        UserDefaults.standard.removeObject(forKey: notebooksKey)
        UserDefaults.standard.removeObject(forKey: playlistsKey)
        
        // Clear songs cache
        clearSongsCache()
    }
    
    // MARK: - Likes
    
    func restoreLikes() {
        if let saved = UserDefaults.standard.array(forKey: likesKey) as? [String] {
            likedPaths = Set(saved)
        }
    }
    
    func saveLikes() {
        UserDefaults.standard.set(Array(likedPaths), forKey: likesKey)
    }
    
    func toggleLike(song: Song) {
        let path = song.url.path
        if likedPaths.contains(path) {
            likedPaths.remove(path)
        } else {
            likedPaths.insert(path)
        }
        saveLikes()
    }
    
    func isLiked(song: Song) -> Bool {
        return likedPaths.contains(song.url.path)
    }
    
    var likedSongs: [Song] {
        return songs.filter { likedPaths.contains($0.url.path) }
                .sorted { 
                    let duration1 = StatsManager.shared.getDuration(for: $0)
                    let duration2 = StatsManager.shared.getDuration(for: $1)
                    
                    if duration1 == duration2 {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return duration1 > duration2
                }
    }
    
    // MARK: - Playlist Management
    
    func createPlaylist(name: String, colorHex: String? = nil, iconEmoji: String? = nil, coverArtData: Data? = nil) {
        let resolvedColor = colorHex ?? Playlist.availableColors.randomElement()
        let newPlaylist = Playlist(name: name, songPaths: [], colorHex: resolvedColor, iconEmoji: iconEmoji, coverArtData: coverArtData, createdAt: Date())
        playlists.append(newPlaylist)
        savePlaylists()
        Logger.shared.log("Created playlist: \(name) with color \(resolvedColor ?? "nil")")
    }
    
    func updatePlaylist(_ playlist: Playlist, newName: String, newColorHex: String?, newIconEmoji: String?, newCoverArt: Data?) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index].name = newName
            playlists[index].colorHex = newColorHex
            playlists[index].iconEmoji = newIconEmoji
            playlists[index].coverArtData = newCoverArt
            savePlaylists()
            Logger.shared.log("Updated playlist: \(newName)")
        }
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists.remove(at: index)
            savePlaylists()
            Logger.shared.log("Deleted playlist: \(playlist.name)")
        }
    }
    
    func addToPlaylist(playlist: Playlist, song: Song) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            // Avoid duplicates
            if !playlists[index].songPaths.contains(song.url.path) {
                playlists[index].songPaths.append(song.url.path)
                savePlaylists()
                Logger.shared.log("Added \(song.title) to playlist \(playlist.name)")
            }
        }
    }
    
    func removeFromPlaylist(playlist: Playlist, song: Song) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            if let songIndex = playlists[index].songPaths.firstIndex(of: song.url.path) {
                playlists[index].songPaths.remove(at: songIndex)
                savePlaylists()
                Logger.shared.log("Removed \(song.title) from playlist \(playlist.name)")
            }
        }
    }
    
    func getSongs(for playlist: Playlist) -> [Song] {
        // Map paths back to loaded songs
        return playlist.songPaths.compactMap { path in
            songs.first(where: { $0.url.path == path })
        }
    }
    
    private func savePlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            UserDefaults.standard.set(data, forKey: playlistsKey)
        } catch {
            Logger.shared.log("Error saving playlists: \(error)", level: .error)
        }
    }
    
    private func restorePlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey) else { return }
        do {
            playlists = try JSONDecoder().decode([Playlist].self, from: data)
            Logger.shared.log("Restored \(playlists.count) playlists")
        } catch {
            Logger.shared.log("Error restoring playlists: \(error)", level: .error)
        }
    }
    
    private func isAudioFile(_ url: URL) -> Bool {
        let extensions = ["mp3", "m4a", "wav", "flac", "aac"]
        return extensions.contains(url.pathExtension.lowercased())
    }
    
    private func processSong(url: URL) async -> Song? {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let asset = AVURLAsset(url: url)
        
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var duration: TimeInterval = 0

        var artworkData: Data? = nil
        var sampleRate: Double? = nil
        var trackNumber: Int? = nil
        
        // --- Robust Metadata Extraction ---
        do {
            // Load all available formats (e.g. ID3, iTunes, Vorbis)
            let formats = try await asset.load(.availableMetadataFormats)
            
            var foundTitle = false
            var foundArtist = false
            var foundAlbum = false
            var foundTrack = false
            var foundArt = false
            
            // Helper to sanitize image data
            func sanitize(_ data: Data) -> Data? {
                if let image = UIImage(data: data),
                   let normalized = image.normalized(),
                   let cleanData = normalized.jpegData(compressionQuality: 0.8) {
                    return cleanData
                }
                return data
            }
            
            // Iterate all formats to find best data
            for format in formats {
                let items = try await asset.loadMetadata(for: format)
                
                for item in items {
                    // 1. Try Common Key first
                    if let commonKey = item.commonKey {
                        switch commonKey {
                        case .commonKeyTitle:
                            if !foundTitle, let value = try? await item.load(.stringValue), !value.isEmpty {
                                title = value
                                foundTitle = true
                            }
                        case .commonKeyArtist:
                            if !foundArtist, let value = try? await item.load(.stringValue), !value.isEmpty {
                                artist = value
                                foundArtist = true
                            }
                        case .commonKeyAlbumName:
                            if !foundAlbum, let value = try? await item.load(.stringValue), !value.isEmpty {
                                album = value
                                foundAlbum = true
                            }
                        case .commonKeyArtwork:
                            if !foundArt, let value = try? await item.load(.dataValue) {
                                artworkData = sanitize(value)
                                foundArt = true
                            }
                        default: break
                        }
                    }
                    
                    // 2. Fallback to Raw Key (String) if not found defined
                    // Useful for Vorbis Comments (FLAC) which might not map to common keys on all iOS versions
                    if let key = (item.key as? String) ?? (item.identifier?.rawValue), !key.isEmpty {
                         // Keys are often upper case in Vorbis "TITLE", "ARTIST" or "TIT2" in ID3
                         let upper = key.uppercased()
                         
                         if !foundTitle && (upper == "TITLE" || upper.contains("TIT2")) {
                             if let value = try? await item.load(.stringValue), !value.isEmpty {
                                 title = value
                                 foundTitle = true
                             }
                         }
                         if !foundArtist && (upper == "ARTIST" || upper.contains("TPE1")) {
                             if let value = try? await item.load(.stringValue), !value.isEmpty {
                                 artist = value
                                 foundArtist = true
                             }
                         }
                         if !foundAlbum && (upper == "ALBUM" || upper.contains("TALB")) {
                             if let value = try? await item.load(.stringValue), !value.isEmpty {
                                 album = value
                                 foundAlbum = true
                             }
                         }
                         
                         // Track Number extraction
                         if !foundTrack {
                             let keyName = key.uppercased()
                             // Common numeric keys or ID3 "TRCK"
                             if keyName == "TRCK" || keyName.contains("TRACK") {
                                 if let value = try? await item.load(.stringValue) {
                                      // Handle "1/12" string format
                                      let components = value.components(separatedBy: "/")
                                      if let first = components.first, let num = Int(first) {
                                          trackNumber = num
                                          foundTrack = true
                                      }
                                 } else if let value = try? await item.load(.numberValue) {
                                     trackNumber = value.intValue
                                     foundTrack = true
                                 }
                             }
                         }
                         
                         // Cover Art in Vorbis can be "METADATA_BLOCK_PICTURE" or similar, 
                         // but AVAsset often exposes it as commonKeyArtwork if it parses it. 
                         // If not, we check for data values associated with "PICTURE" or "COVER".
                         if !foundArt && (upper.contains("PICTURE") || upper.contains("COVER") || upper == "APIC") {
                             if let value = try? await item.load(.dataValue) {
                                 artworkData = sanitize(value)
                                 foundArt = true
                             }
                         }
                    }
                }
            }
            
            // Duration
            let durationTime = try await asset.load(.duration)
            duration = CMTimeGetSeconds(durationTime)
            if duration.isNaN { duration = 0 }
            
            // Extract Sample Rate from Tracks
            let tracks = try await asset.load(.tracks)
            if let audioTrack = tracks.first(where: { $0.mediaType == .audio }) {
                let formatDescriptions = try await audioTrack.load(.formatDescriptions)
                if let formatDesc = formatDescriptions.first {
                    if let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                        sampleRate = basicDesc.pointee.mSampleRate
                    }
                }
            }
            
        } catch {
            print("Error loading metadata for \(url.lastPathComponent): \(error)")
        }
        
        // Extended Audio Quality Extraction (Bitrate, BitDepth, Lossless) - Kept same logic
        var bitrate: Int? = nil
        var bitDepth: Int? = nil
        var isLossless: Bool = false
        
        do {
            let tracks = try await asset.load(.tracks)
            if let audioTrack = tracks.first(where: { $0.mediaType == .audio }) {
                let estimatedRate = try await audioTrack.load(.estimatedDataRate)
                if estimatedRate > 0 { bitrate = Int(estimatedRate) }
                
                let formatDescriptions = try await audioTrack.load(.formatDescriptions)
                if let formatDesc = formatDescriptions.first {
                    if let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                        let depth = basicDesc.pointee.mBitsPerChannel
                        if depth > 0 { bitDepth = Int(depth) }
                        
                        let formatID = basicDesc.pointee.mFormatID
                        if formatID == kAudioFormatLinearPCM || formatID == kAudioFormatAppleLossless { isLossless = true }
                        else if formatID == kAudioFormatFLAC { isLossless = true }
                    }
                }
            }
        } catch {}
        
        // Compute search index once
        let rawString = "\(title) \(artist) \(album)"
        let searchIndex = rawString.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        
        // Get file modification date for cache validation
        var fileModDate: Date? = nil
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            fileModDate = attributes[.modificationDate] as? Date
        } catch {
            // If we can't get modification date, that's okay
        }
        
        return Song(id: UUID(), url: url, title: title, artist: artist, album: album, trackNumber: trackNumber, duration: duration, searchIndex: searchIndex, artworkData: artworkData, sampleRate: sampleRate, bitrate: bitrate, bitDepth: bitDepth, isLossless: isLossless, fileModificationDate: fileModDate)

    }
}

import MediaPlayer

// MARK: - Audio Player Manager

// MARK: - Playback Context
enum PlaybackContext: Equatable {
    case allSongs
    case playlist(id: UUID)
    case album(name: String)
    case artist(name: String)
}

class AudioPlayerManager: ObservableObject {
    @Published var currentSong: Song?
    @Published var currentContext: PlaybackContext?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var totalTime: TimeInterval = 0
    @Published var currentQueue: [Song] = []
    
    // 3D Audio Toggle
    @Published var is3DAudioEnabled: Bool = false {
        didSet {
            updateReverb()
            UserDefaults.standard.set(is3DAudioEnabled, forKey: "is3DAudioEnabled")
        }
    }
    
    // Liquid Glass Preference
    @Published var isLiquidGlassEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isLiquidGlassEnabled, forKey: "isLiquidGlassEnabled")
        }
    }
    
    // Visibility Preferences
    @Published var showGameButton: Bool = false {
        didSet {
            UserDefaults.standard.set(showGameButton, forKey: "showGameButton")
        }
    }
    
    @Published var show3DButton: Bool = true {
        didSet {
            UserDefaults.standard.set(show3DButton, forKey: "show3DButton")
        }
    }

    
    // Shuffle
    @Published var isShuffleEnabled: Bool = false
    private var originalQueue: [Song] = []

    
    // Persistence Key
    private let lastPlayedSongKey = "last_played_song_path"
    
    // EQ State
    @Published var isEQActive: Bool = false
    
    // Audio Engine Components
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    // Intermediate Mixer for Format Conversion
    private let mixerNode = AVAudioMixerNode()
    // 3D Audio Effect
    private var reverbNode = AVAudioUnitReverb()
    // Parametric EQ
    private let eqNode = AVAudioUnitEQ(numberOfBands: 6)
    
    // DJ Effects
    private let djFilterNode = AVAudioUnitEQ(numberOfBands: 1) // For Filter effect
    private let varispeedNode = AVAudioUnitVarispeed() // For Scratch effect
    @Published var isCutterActive: Bool = false
    @Published var isFilterActive: Bool = false
    @Published var isStutterActive: Bool = false
    @Published var scratchRate: Float = 1.0 // 0.25 to 4.0, 1.0 = normal
    
    // Nightcore Mode
    @Published var isNightcoreActive: Bool = false {
        didSet {
            UserDefaults.standard.set(isNightcoreActive, forKey: "isNightcoreActive")
            updateNightcore()
        }
    }
    
    private var cutterTimer: Timer?
    private var stutterTimer: Timer?
    private var cutterPhase: Bool = false // Toggles volume on/off
    
    // EQ Persistence
    private let eqGainsKey = "user_eq_gains"
    
    // Band Frequencies (Fixed for Parametric UI)
    // Bass, Low-Mid, Mid, High-Mid, Presence, Brilliance
    let eqFrequencies: [Float] = [60, 170, 310, 600, 3000, 14000]
    
    private var audioFile: AVAudioFile?
    private var trackSampleRate: Double = 44100.0
    private var timer: Timer?
    private var seekFrame: AVAudioFramePosition = 0
    private var statsAccumulator: TimeInterval = 0

    private var activeSecurityScopedURL: URL? // Track accessed file
    
    // Playback History
    private var playbackHistory: [(song: Song, queue: [Song], context: PlaybackContext?)] = []

    
    init() {
        self.isShuffleEnabled = UserDefaults.standard.bool(forKey: "isShuffleEnabled")
        self.is3DAudioEnabled = UserDefaults.standard.bool(forKey: "is3DAudioEnabled")
        
        // Liquid Glass Default (True if not set, or loading existing value)
        if UserDefaults.standard.object(forKey: "isLiquidGlassEnabled") == nil {
            self.isLiquidGlassEnabled = true // Default ON
        } else {
            self.isLiquidGlassEnabled = UserDefaults.standard.bool(forKey: "isLiquidGlassEnabled")
        }
        
        // Visibility Defaults (True if not set)
        if UserDefaults.standard.object(forKey: "showGameButton") == nil {
            self.showGameButton = false
        } else {
            self.showGameButton = UserDefaults.standard.bool(forKey: "showGameButton")
        }
        
        if UserDefaults.standard.object(forKey: "show3DButton") == nil {
            self.show3DButton = true
        } else {
            self.show3DButton = UserDefaults.standard.bool(forKey: "show3DButton")
        }
        
        setupAudioSession()
        setupEngine()
        setupEQ() // NEW: Configure EQ bands
        setupRemoteTransportControls() // Kept original method name
        setupNotifications()
        
        // Apply initial state
        updateReverb()
        
        if UserDefaults.standard.object(forKey: "isNightcoreActive") != nil {
            self.isNightcoreActive = UserDefaults.standard.bool(forKey: "isNightcoreActive")
        }
        updateNightcore()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(mixerNode) // Attach Mixer
        engine.attach(reverbNode)
        
        // Configure Reverb for "3D" feel
        // Changed to Medium Chamber for a "fuller" sound that isn't as distant as Large Hall
        reverbNode.loadFactoryPreset(.mediumChamber)
        reverbNode.wetDryMix = 0 // Start dry, updateReverb() will set it
        
        // Attach EQ
        engine.attach(eqNode)
        
        // Attach DJ Effects (Filter, Varispeed)
        engine.attach(djFilterNode)
        engine.attach(varispeedNode)
        
        // Connect: Player -> Mixer -> EQ -> Filter -> Varispeed -> Reverb -> MainMixer
        engine.connect(mixerNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: djFilterNode, format: nil)
        engine.connect(djFilterNode, to: varispeedNode, format: nil)
        engine.connect(varispeedNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: nil)
        
        engine.prepare()
        
        do {
            try engine.start()
        } catch {
            print("Engine start error: \(error)")
        }
        
        // Configure DJ Effects
        setupDJEffects()
    }
    
    private func updateReverb() {
        // Toggle effect: 15% wet to add space/width without washing out clarity (was 50%)
        reverbNode.wetDryMix = is3DAudioEnabled ? 15 : 0
    }
    
    private func updateNightcore() {
        // Nightcore Effect: Speed up by 25% (1.25x), which also raises pitch proportionally
        varispeedNode.rate = isNightcoreActive ? 1.25 : 1.0
    }
    
    // Legacy support or alias
    private func updateEngineConfiguration() {
        updateReverb()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleInterruption),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance())
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleRouteChange),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: AVAudioSession.sharedInstance())
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, self.audioFile != nil else { return .commandFailed }
            self.playInternal()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.isPlaying else { return .commandFailed }
            self.pauseInternal()
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
             self?.previous()
             return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
    }
    
    func play(song: Song, queue: [Song], context: PlaybackContext? = nil, autoPlay: Bool = true, addToHistory: Bool = true, keepQueue: Bool = false) {
        // Add to history before switching song
        if addToHistory, let current = currentSong {
             playbackHistory.append((song: current, queue: currentQueue, context: currentContext))
        }

        if isShuffleEnabled && !keepQueue {
            // New shuffle initiation
            self.originalQueue = queue
            if let context = context { self.currentContext = context }
            
            // Create shuffled queue starting with 'song'
            var newQueue = queue.shuffled()
            // Move target song to front
            if let idx = newQueue.firstIndex(where: { $0.id == song.id }) {
                newQueue.remove(at: idx)
                newQueue.insert(song, at: 0)
            }
            self.currentQueue = newQueue
        } else {
            // Standard playback or continuing existing queue
            if !keepQueue {
                self.currentQueue = queue
                if let context = context {
                    self.currentContext = context
                }
            } else {
                 // We are keeping the queue, but if the new song isn't in it, we should probably warn or handle?
                 // For now assumes the caller knows what they are doing (picking from currentQueue).
            }
        }

        
        if let current = currentSong, current.id == song.id {
            if autoPlay {
                if isPlaying { pauseInternal() } else { playInternal() }
            } else {
                 playInternal() // Ensure engine ready
                 pauseInternal() // Then Pause
            }
            return
        }
        
        // New song
        stop()
        
        currentSong = song
        totalTime = song.duration
        
        // Load File
        // Load File
        do {
            // Start accessing security scoped resource for playback
            // Optimize: Only request access if we don't already have it (e.g. via parent folder)
            if FileManager.default.isReadableFile(atPath: song.url.path) {
                // We have access (likely inherited from folder bookmark)
                // No need to explicitly start accessing, but we can try just in case it's a direct bookmark
                // However, avoiding the FALSE failure log is the goal.
            } else {
                 if song.url.startAccessingSecurityScopedResource() {
                     activeSecurityScopedURL = song.url
                 } else {
                     Logger.shared.log("Failed to access security scoped resource for playback", level: .warning)
                 }
            }


            
            // Verify file existence before attempting playback
            if !FileManager.default.fileExists(atPath: song.url.path) {
                Logger.shared.log("File does not exist at path: \(song.url.path)", level: .error)
                // Fallback: This might be a stale path if the user moved the file. 
                // In a future update, we could try to re-resolve it if we had a bookmark for the *file* specifically, 
                // but we rely on folder bookmarks.
            }

            let file = try AVAudioFile(forReading: song.url)

            // self.audioFile = file // Move assignment later to ensure setting up assumes success

            self.trackSampleRate = file.processingFormat.sampleRate
            
            // Re-connect Player Output to Mixers based on file format
            let format = file.processingFormat
            engine.disconnectNodeOutput(playerNode)
            
            // Connect: Player -> Mixer (Format)
            // Mixer handles conversion to downstream format automatically.
            engine.connect(playerNode, to: mixerNode, format: format)
            
            // Ensure mixer status
            
            // Ensure mixer status
            updateReverb()
            
            // Assign file now that connections are likely good
            self.audioFile = file
            
            // Schedule
            seekFrame = 0
            scheduleFile()
            
            // Start Engine if not running
            if !engine.isRunning {
                try engine.start()
            }
            
            if autoPlay {
                playInternal()
            } else {
                // Just update info, don't play
                updateNowPlayingInfo()
            }
            
            saveLastPlayedSong(song)
            Logger.shared.log("Playing (Seamless Engine): \(song.title)")
            
        } catch {
            print("Error loading file: \(error)")
        }
    }
    
    private func scheduleFile() {
        guard let file = audioFile else { return }
        
        // We schedule from seekFrame to end
        // FrameCount = total - seekFrame
        let framesToPlay = AVAudioFrameCount(file.length - seekFrame)
        guard framesToPlay > 0 else { return }
        
        playerNode.scheduleSegment(file, startingFrame: seekFrame, frameCount: framesToPlay, at: nil) { [weak self] in
            // Completion handler logic (End of track)
            // Note: This is called when segment finishes OR node stops.
            // We need to differentiate natural finish vs stop.
            // For now, if we are 'playing', we assume natural finish?
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isPlaying && self.playerNode.isPlaying {
                     // Auto-Next? 
                     // Careful: scheduleSegment completion is sometimes non-main thread
                }
            }
        }
        // Actually, reliable EOF detection in AVAudioEngine is tricky. 
        // We'll rely on time comparison in the timer.
    }
    
    private func playInternal() {
        // Ensure engine is running
        if !engine.isRunning {
             do {
                 try engine.start()
             } catch {
                 Logger.shared.log("Failed to start engine: \(error)", level: .error)
                 return
             }
        }
        
        // Check if playerNode is connected (prevent crash)
        // Verify output format is set (proxy for connection)
        if engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
             Logger.shared.log("Attempted to play disconnected node. Re-initializing...", level: .error)
             // Try to re-connect if we have current song? 
             // Ideally we just return to avoid crash. The user might need to re-select song.
             return
        }
        
        playerNode.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
    }
    
    func pause() {
        pauseInternal()
    }
    
    private func pauseInternal() {
        playerNode.pause()
        isPlaying = false
        // Flush stats on pause
        if let song = currentSong, statsAccumulator > 0 {
            StatsManager.shared.logListen(song: song, seconds: statsAccumulator)
            statsAccumulator = 0
        }
        stopTimer()
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pauseInternal()
        } else {
            playInternal()
        }
    }
    
    func toggleShuffle() {
        isShuffleEnabled.toggle()
        if isShuffleEnabled {
            // Enable Shuffle
            // 1. Save current order
            originalQueue = currentQueue
            
            // 2. Shuffle current queue
            if let current = currentSong { // Maintain current song
                var newQueue = currentQueue.shuffled()
                if let idx = newQueue.firstIndex(where: { $0.id == current.id }) {
                    newQueue.remove(at: idx)
                    newQueue.insert(current, at: 0)
                }
                currentQueue = newQueue
            } else {
                currentQueue.shuffle()
            }
        } else {
            // Disable Shuffle
            // Restore original order
            // Ideally we find the current song in the original queue and play from there or simply restore list?
            // If we restore list, 'next' will be the song after current in original list.
            if !originalQueue.isEmpty {
                // Determine context. If originalQueue had the current song, we just switch the list back.
                currentQueue = originalQueue
            }
        }
    }

    
    func next() {
        guard let current = currentSong, !currentQueue.isEmpty, let idx = currentQueue.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIdx = (idx + 1) % currentQueue.count
        // keepQueue: true prevents re-shuffling
        play(song: currentQueue[nextIdx], queue: currentQueue, keepQueue: true)
    }
    
    func previous() {
        // If > 3 seconds, restart song
        if currentTime > 3.0 {
            seek(to: 0)
            if !isPlaying { playInternal() }
            return
        }
        
        // If history exists, pop it (Priority over queue order)
        if !playbackHistory.isEmpty {
            let last = playbackHistory.removeLast()
            // Restore state: Don't add to history again when going back
            play(song: last.song, queue: last.queue, context: last.context, addToHistory: false, keepQueue: false) // keepQueue false puts the restored queue back as active
            return
        }
        
        // Fallback to queue order if no history
        guard let current = currentSong, !currentQueue.isEmpty, let idx = currentQueue.firstIndex(where: { $0.id == current.id }) else { return }
        let prevIdx = (idx - 1 + currentQueue.count) % currentQueue.count
        play(song: currentQueue[prevIdx], queue: currentQueue, addToHistory: false, keepQueue: true)
    }
    
    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        playerNode.stop() // Must stop to reschedule
        
        // Calculate frame
        if let file = audioFile {
            let frame = AVAudioFramePosition(time * trackSampleRate)
            seekFrame = max(0, min(frame, file.length - 1))
        }
        
        currentTime = time
        scheduleFile()
        
        if wasPlaying {
            playInternal()
        } else {
            updateNowPlayingInfo()
        }
    }
    
    func stop() {
        playerNode.stop()
        engine.stop()
        timer?.invalidate()
        audioFile = nil
        currentSong = nil
        isPlaying = false

        
        // Stop accessing security scoped resource
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil

        
        // Flush stats on stop
        if let song = currentSong, statsAccumulator > 0 {
            StatsManager.shared.logListen(song: song, seconds: statsAccumulator)
        }
        statsAccumulator = 0
                currentTime = 0
        totalTime = 0
        updateNowPlayingInfo()
    }
    
    // Timer for UI Update & End Detection
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.playerNode.isPlaying, let nodeTime = self.playerNode.lastRenderTime, let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                // Calculate current time
                // currentTime = seekOffset + playedTime
                 let playedFrames = playerTime.sampleTime
                 let currentFrames = self.seekFrame + playedFrames
                 self.currentTime = Double(currentFrames) / self.trackSampleRate
                 
                 // Check EOF
                 if self.currentTime >= self.totalTime - 0.2 { // Buffer for end
                     self.next()
                 }
                 
                 // Log Stats (Throttled)
                 if let song = self.currentSong {
                     self.statsAccumulator += 0.1
                     if self.statsAccumulator >= 5.0 {
                         StatsManager.shared.logListen(song: song, seconds: self.statsAccumulator)
                         self.statsAccumulator = 0
                     }
                 }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Handlers
    
    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            pauseInternal()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                try? engine.start()
                playInternal()
            }
        @unknown default: break
        }
    }
    
    @objc func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        if reason == .oldDeviceUnavailable {
            pauseInternal()
        }
    }
    
    func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = song.album
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = song.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        if let data = song.artworkData, let image = UIImage(data: data) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - Persistence
    
    private func saveLastPlayedSong(_ song: Song) {
        UserDefaults.standard.set(song.url.path, forKey: lastPlayedSongKey)
    }
    
    func restoreLastState(from songs: [Song]) {
        guard !songs.isEmpty else { return }
        if let savedPath = UserDefaults.standard.string(forKey: lastPlayedSongKey),
           let song = songs.first(where: { $0.url.path == savedPath }) {
            // Load the song fully but paused
            play(song: song, queue: songs, autoPlay: false)

            Logger.shared.log("Restored last played song: \(song.title)")
        } else if let firstSong = songs.first {
            self.currentQueue = songs
            self.currentSong = firstSong
            self.totalTime = firstSong.duration
        }
        updateNowPlayingInfo()
    }
    // MARK: - Equaliser
    
    private func setupEQ() {
        // Configure bands
        for (index, freq) in eqFrequencies.enumerated() {
            let band = eqNode.bands[index]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0 // Q-factor, 1 octave roughly
            band.bypass = false
        }
        
        // Load saved gains
        if let savedGains = UserDefaults.standard.array(forKey: eqGainsKey) as? [Float], savedGains.count == eqFrequencies.count {
            for (index, gain) in savedGains.enumerated() {
                eqNode.bands[index].gain = gain
            }
        }
        
        // Initial state check
        let gains = eqNode.bands.map { $0.gain }
        isEQActive = gains.contains { abs($0) > 0.1 }
    }
    
    func updateEQ(gains: [Float]) {
        guard gains.count == eqFrequencies.count else { return }
        for (index, gain) in gains.enumerated() {
            eqNode.bands[index].gain = gain
        }
        isEQActive = gains.contains { abs($0) > 0.1 }
        saveEQ(gains: gains)
    }
    
    func resetEQ() {
        let zeros = [Float](repeating: 0.0, count: eqFrequencies.count)
        updateEQ(gains: zeros)
    }
    
    func getCurrentEQGains() -> [Float] {
        return eqNode.bands.map { $0.gain }
    }
    
    private func saveEQ(gains: [Float]) {
        UserDefaults.standard.set(gains, forKey: eqGainsKey)
    }
    
    // MARK: - DJ Effects
    
    // MARK: - DJ Effects
    
    private func setupDJEffects() {
        // Filter: Low-pass filter for "muffled" effect
        let filterBand = djFilterNode.bands[0]
        filterBand.filterType = .lowPass
        filterBand.frequency = 800 // Cuts highs aggressively when active
        filterBand.bypass = true // Start bypassed
    }
    
    // Cutter: Rhythmic volume gating (8th notes at ~120bpm = 250ms)
    func setCutter(_ active: Bool) {
        isCutterActive = active
        if active {
            cutterPhase = true
            cutterTimer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.cutterPhase.toggle()
                self.engine.mainMixerNode.outputVolume = self.cutterPhase ? 1.0 : 0.0
            }
        } else {
            cutterTimer?.invalidate()
            cutterTimer = nil
            engine.mainMixerNode.outputVolume = 1.0 // Restore volume
        }
    }
    
    // Stutter: Rapid volume gating (32nd notes at ~120bpm = ~62ms)
    func setStutter(_ active: Bool) {
        isStutterActive = active
        if active {
            cutterPhase = true // Reuse phase variable
            stutterTimer = Timer.scheduledTimer(withTimeInterval: 0.0625, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.cutterPhase.toggle()
                self.engine.mainMixerNode.outputVolume = self.cutterPhase ? 1.0 : 0.0
            }
        } else {
            stutterTimer?.invalidate()
            stutterTimer = nil
            engine.mainMixerNode.outputVolume = 1.0 // Restore volume
        }
    }
    
    // Filter: Engage low-pass filter
    func setFilter(_ active: Bool) {
        isFilterActive = active
        djFilterNode.bands[0].bypass = !active
    }
    
    // Scratch: Dynamic playback rate control (0.25 to 4.0)
    func setScratchRate(_ rate: Float) {
        // Clamp to valid range
        let clampedRate = max(0.25, min(4.0, rate))
        scratchRate = clampedRate
        varispeedNode.rate = clampedRate
    }
    
    // Reset scratch to normal speed
    func resetScratch() {
        scratchRate = 1.0
        varispeedNode.rate = 1.0
    }
}

extension Notification.Name {
    static let requestNextTrack = Notification.Name("requestNextTrack")
    static let requestPreviousTrack = Notification.Name("requestPreviousTrack")
}
