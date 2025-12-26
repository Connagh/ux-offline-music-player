import SwiftUI
import UniformTypeIdentifiers

enum ActiveSheet: Identifiable {
    case folderPicker
    case settings
    case addToPlaylist(Song)
    case createPlaylist
    case globalStats
    case itemStats(context: StatsContext)
    case paywall
    
    var id: String {
        switch self {
        case .folderPicker: return "folderPicker"
        case .settings: return "settings"
        case .addToPlaylist(let song): return "addToPlaylist-\(song.id)"
        case .createPlaylist: return "createPlaylist"
        case .globalStats: return "globalStats"
        case .itemStats(let context):
            switch context {
            case .song(let s): return "itemStats-song-\(s.id)"
            case .artist(let n): return "itemStats-artist-\(n)"
            case .album(let n): return "itemStats-album-\(n)"
            case .playlist(let p): return "itemStats-playlist-\(p.id)"
            }
        case .paywall: return "paywall"
        }
    }
}

struct SongListView: View {
    @ObservedObject var bookmarkManager: BookmarkManager
    @ObservedObject var playerManager: AudioPlayerManager
    @ObservedObject var storeManager = StoreManager.shared
    // Removed local searchText and filtering state
    
    // Playlist states
    @State private var viewMode: ViewMode = .songs
    @State private var songToAddTimestamp: Song?
    
    @State private var localSearchText: String = ""
    
    // Performance Optimization: Cache filtered results to avoid main thread blocking
    @State private var cachedArtists: [(name: String, count: Int, songs: [Song])] = []
    @State private var cachedAlbums: [(name: String, count: Int, songs: [Song])] = []
    @State private var cachedFilteredLikes: [Song] = []
    @State private var totalArtistsCount: Int = 0

    @State private var totalAlbumsCount: Int = 0
    @State private var isComputingFilters = false

    
    // Sheet Management
    @State private var activeSheet: ActiveSheet?
    @State private var newPlaylistName = ""
    @State private var showImportOptions = false
    @State private var selectedImportURL: URL? = nil

    @FocusState private var isSearchFocused: Bool
    
    enum ViewMode {
        case songs
        case playlists
        case likes
        case artists
        case albums
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Search Bar
                    // Search Bar
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            
                            TextField("Search", text: $localSearchText)
                                .foregroundColor(.white)
                                .accentColor(.offlineOrange)
                                .focused($isSearchFocused)
                                .submitLabel(.search)
                                .task(id: localSearchText) {
                                    do {
                                        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                                        if !Task.isCancelled {
                                            bookmarkManager.searchText = localSearchText
                                        }
                                    } catch {}
                                }
                                // Debounce logic handled via .task(id: localSearchText)
                            
                            if !localSearchText.isEmpty {
                                Button(action: {
                                    localSearchText = ""
                                    bookmarkManager.searchText = "" // Sync immediately on clear
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.offlineDarkGray)
                        .cornerRadius(10)
                        

                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    
                    // Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ChipView(title: "Songs", isSelected: viewMode == .songs) {
                                viewMode = .songs
                            }
                            
                            
                            ChipView(title: "Playlists", isSelected: viewMode == .playlists) {
                                viewMode = .playlists
                            }
                            
                            ChipView(title: "Likes", isSelected: viewMode == .likes) {
                                viewMode = .likes
                            }
                            
                            ChipView(title: "Artists", isSelected: viewMode == .artists) {

                                viewMode = .artists
                            }
                            
                            ChipView(title: "Albums", isSelected: viewMode == .albums) {
                                viewMode = .albums
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 10)
                    .scrollDismissesKeyboard(.interactively)
                    
                    // Main Content
                    ZStack {
                        if viewMode == .songs {
                            // If searching, show filtered songs using same view
                            if !bookmarkManager.searchText.isEmpty {
                                ScrollViewReader { proxy in
                                    songsView(proxy: proxy)
                                }
                            } else {
                                if bookmarkManager.songs.isEmpty && !bookmarkManager.isImporting {
                                VStack(spacing: 20) {
                                    Spacer()
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                    Text("No music found")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                    Text("To get started, add a folder that contains music files.")
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    
                                    Button(action: {
                                        showImportOptions = true
                                    }) {
                                        Text("Import Music")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 12)
                                            .background(Color.offlineOrange)
                                            .cornerRadius(10)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollViewReader { proxy in
                                    songsView(proxy: proxy)
                                }
                            }
                        }
                    } else if viewMode == .likes {
                            if bookmarkManager.likedSongs.isEmpty {
                                VStack(spacing: 20) {
                                    Image(systemName: "heart.slash")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                    Text("No liked songs yet")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                    Text("Tap the heart icon on the player bar to add songs to your likes.")
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            } else {
                                // Filtered Likes
                                let source = cachedFilteredLikes
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(source) { song in
                                            Button(action: {
                                                // Play from the filtered list (filtering preserves sort order usually, or we can enforce it)
                                                playerManager.play(song: song, queue: source, context: .allSongs)
                                            }) {
                                                SongRowContent(song: song, playerManager: playerManager, bookmarkManager: bookmarkManager, context: .allSongs)
                                            }
                                            Divider().background(Color.gray.opacity(0.1)).padding(.leading, 72)
                                        }
                                        searchResultFooter(filtered: source.count, total: bookmarkManager.likedSongs.count)
                                    }
                                    .padding(.bottom, 150)
                                }
                                .scrollDismissesKeyboard(.interactively)
                            }
                        } else if viewMode == .playlists {

                            playlistsView
                        } else if viewMode == .artists {
                            artistsView
                        } else if viewMode == .albums {
                            albumsView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { activeSheet = .settings }) {
                        Image(systemName: "gearshape")
                            .imageScale(.medium)
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 20) {
                        Button(action: {
                            if storeManager.isPremium {
                                activeSheet = .globalStats
                            } else {
                                activeSheet = .paywall
                            }
                        }) {
                            Image(systemName: "chart.bar.xaxis")
                                .imageScale(.medium)
                        }
                        .foregroundColor(.white)
                        
                        Button(action: { showImportOptions = true }) {
                            Image(systemName: "folder.badge.plus")
                                .imageScale(.medium)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .navigationViewStyle(.stack)
        .confirmationDialog("Import Music", isPresented: $showImportOptions, titleVisibility: .visible) {
            Button("Add a folder") {
                selectedImportURL = nil
                activeSheet = .folderPicker
            }
            
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add a music folder from 'On My iPhone' or 'iCloud Drive'.")
        }
        .sheet(item: $activeSheet) { item in
            switch item {
            case .folderPicker:
                FolderPicker(bookmarkManager: bookmarkManager, activeSheet: $activeSheet, initialDirectory: selectedImportURL)
            case .settings:
                SettingsView(bookmarkManager: bookmarkManager, playerManager: playerManager)
            case .addToPlaylist(let song):
                AddToPlaylistView(bookmarkManager: bookmarkManager, song: song, isShowing: Binding(
                    get: { true },
                    set: { _ in activeSheet = nil }
                ))
            case .createPlaylist:
                CreatePlaylistView(bookmarkManager: bookmarkManager, isPresented: Binding(
                    get: { true },
                    set: { if !$0 { activeSheet = nil } }
                ))
            case .globalStats:
                GlobalStatsView(songs: $bookmarkManager.songs, playlists: $bookmarkManager.playlists)
            case .itemStats(let context):
                StatsDetailView(context: context, allSongs: bookmarkManager.songs, bookmarkManager: bookmarkManager, playerManager: playerManager)
            case .paywall:
                PaywallView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestNextTrack)) { _ in
            playerManager.next()
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestPreviousTrack)) { _ in
            playerManager.previous()
        }
        .alert(isPresented: $bookmarkManager.showImportAlert) {
            Alert(
                title: Text("Import from iCloud?"),
                message: Text("This folder contains \(bookmarkManager.pendingImportAnalysis?.cloudFiles ?? 0) files that will need to be downloaded to the app.\n\nThis folder can be removed at any time."),
                primaryButton: .default(Text("Import"), action: {
                    bookmarkManager.confirmImport()
                }),
                secondaryButton: .cancel(Text("Cancel"), action: {
                    bookmarkManager.cancelImport()
                })
            )
        }
        .task(id: bookmarkManager.songs) {
            updateFilteredData()
        }
        .task(id: bookmarkManager.searchText) {
            updateFilteredData()
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func songsView(proxy: ScrollViewProxy?) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Determine source: All Songs or Filtered
                let source = !bookmarkManager.searchText.isEmpty ? bookmarkManager.filteredSongs : bookmarkManager.songs
                
                // Shuffle Play Action (Header) - TODO: Reimplement
                // Show button only if we have songs

                Color.clear.frame(height: 1).id("TopAnchor")
                
                // Progress Indicator
                // Progress Indicator / Skeleton
                    if bookmarkManager.isImporting && bookmarkManager.songs.isEmpty {
                         // Skeleton Loader (Only if empty)
                         ForEach(0..<15, id: \.self) { _ in
                             SkeletonRow()
                                 .padding(.horizontal)
                         }
                    }
                
                // Filtering Skeleton
                 if bookmarkManager.isFiltering {
                    ForEach(0..<15, id: \.self) { _ in
                        SkeletonRow()
                            .padding(.horizontal)
                    }
                 } else {
                     ForEach(source) { song in
                        Button(action: {
                            playerManager.play(song: song, queue: source, context: .allSongs)
                        }) {
                            SongRowContent(song: song, playerManager: playerManager, bookmarkManager: bookmarkManager, context: .allSongs)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu {
                            Button {
                                activeSheet = .addToPlaylist(song)
                            } label: {
                                Label("Add to Playlist", systemImage: "plus.circle")
                            }
                            
                            Button {
                                activeSheet = .itemStats(context: .song(song))
                            } label: {
                                Label("Details", systemImage: "info.circle")
                            }
                        }
                        
                        Divider()
                            .background(Color.gray.opacity(0.1))
                            .padding(.leading, 72)
                    }
                 }
                
                // Load More
                if bookmarkManager.hasMoreSearchResults {
                    Button(action: {
                        bookmarkManager.loadAllResults()
                        withAnimation {
                            proxy?.scrollTo("TopAnchor", anchor: .top)
                        }
                    }) {
                        Text("View all results")
                            .foregroundColor(.offlineOrange)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.offlineDarkGray.opacity(0.5))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                searchResultFooter(filtered: source.count, total: bookmarkManager.songs.count)
            }
            .padding(.bottom, 150)
            .padding(.top, 10)
            .padding(.top, 10)
        }
        .scrollDismissesKeyboard(.interactively)

        .onChange(of: bookmarkManager.searchText) { oldValue, text in
             withAnimation {
                 proxy?.scrollTo("TopAnchor", anchor: .top)
             }
        }
        .onChange(of: playerManager.currentSong) { oldSong, newSong in
            if playerManager.isShuffleEnabled, 
               let song = newSong, 
               playerManager.currentContext == .allSongs { // Ensure we are viewing "All Songs" context
                withAnimation {
                    proxy?.scrollTo(song.id, anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Search Filtering Helper
    
    private var filteredPlaylists: [Playlist] {
        let playlists = bookmarkManager.playlists
        let sorted = playlists.sorted {
            StatsManager.shared.getDuration(forPlaylist: $0, allSongs: bookmarkManager.songs) >
            StatsManager.shared.getDuration(forPlaylist: $1, allSongs: bookmarkManager.songs)
        }
        guard !bookmarkManager.searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(bookmarkManager.searchText) }
    }
    
    private func updateFilteredData() {
        // Don't restart if already computing? Actually we should restart/cancel previous.
        // Task automatically handles strict ordering if we don't store it?
        // But for UI state:
        Task {
            await MainActor.run { isComputingFilters = true }
            
            // Artists (Already sorted by getArtists optimization)
            let artists = getArtists(from: bookmarkManager.songs)
            
            let finalArtists: [(name: String, count: Int, songs: [Song])] = !bookmarkManager.searchText.isEmpty ?
                artists.filter { $0.name.localizedCaseInsensitiveContains(bookmarkManager.searchText) } :
                artists
            
            // Albums
             let albums = Dictionary(grouping: bookmarkManager.songs, by: { $0.album })
                .map { (key, value) -> (name: String, count: Int, songs: [Song], duration: TimeInterval) in
                    let sortedSongs = value.sorted {
                        if let t1 = $0.trackNumber, let t2 = $1.trackNumber {
                            return t1 < t2
                        }
                        return $0.title < $1.title
                    }
                     // Optimization: Calculate duration from grouping
                    let duration = value.reduce(0) { $0 + StatsManager.shared.getDuration(for: $1) }
                    return (name: key, count: value.count, songs: sortedSongs, duration: duration)
                }
                .sorted {
                    if $0.duration == $1.duration {
                        // Tie-breaker: Randomize using first song's UUID
                        return ($0.songs.first?.id.uuidString ?? "") < ($1.songs.first?.id.uuidString ?? "")
                    }
                    return $0.duration > $1.duration
                }
                .map { (name: $0.name, count: $0.count, songs: $0.songs) }
            
            let finalAlbums: [(name: String, count: Int, songs: [Song])] = !bookmarkManager.searchText.isEmpty ?
                albums.filter { $0.name.localizedCaseInsensitiveContains(bookmarkManager.searchText) } :
                albums
            
            
            // Likes
            let likes = bookmarkManager.likedSongs
            let finalLikes: [Song]
            if !bookmarkManager.searchText.isEmpty {
                 finalLikes = likes.filter { song in
                    song.title.localizedCaseInsensitiveContains(bookmarkManager.searchText) ||
                    song.artist.localizedCaseInsensitiveContains(bookmarkManager.searchText) ||
                    song.album.localizedCaseInsensitiveContains(bookmarkManager.searchText)
                }
            } else {
                finalLikes = likes
            }
            
            await MainActor.run {
                self.cachedArtists = finalArtists
                self.cachedAlbums = finalAlbums
                self.cachedFilteredLikes = finalLikes
                self.totalArtistsCount = artists.count
                self.totalAlbumsCount = albums.count
                self.isComputingFilters = false
            }
        }
    }
    
    var aggregatedSearchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if isComputingFilters {
                     Section(header: sectionHeader(title: "Loading results...")) {
                         ForEach(0..<10, id: \.self) { _ in
                             SkeletonRow().padding(.horizontal)
                         }
                     }
                } else {
                // 1. Playlists
                if !filteredPlaylists.isEmpty {
                    Section(header: sectionHeader(title: "Playlists")) {
                        ForEach(filteredPlaylists) { playlist in
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist, bookmarkManager: bookmarkManager, playerManager: playerManager)) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        if let hex = playlist.colorHex {
                                            Rectangle()
                                                .fill(Color(hex: hex))
                                                .frame(width: 44, height: 44)
                                                .cornerRadius(6)
                                        } else {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 44, height: 44)
                                                .cornerRadius(6)
                                        }
                                        if let emoji = playlist.iconEmoji {
                                            Text(emoji)
                                                .font(.title3)
                                        } else {
                                            Image(systemName: "music.note.list")
                                                .foregroundColor(.white)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text("\(playlist.songPaths.count) songs")
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(.gray)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                                .background(Color.offlineBackground)
                                .contentShape(Rectangle())
                            }
                            
                            .contextMenu {
                                Button(role: .destructive) {
                                    bookmarkManager.deletePlaylist(playlist)
                                } label: {
                                    Label("Delete Playlist", systemImage: "trash")
                                }
                                
                                Button {
                                    activeSheet = .itemStats(context: .playlist(playlist))
                                } label: {
                                    Label("Details", systemImage: "info.circle")
                                }
                            }
                            Divider().background(Color.gray.opacity(0.1)).padding(.leading, 72)
                        }
                    }
                }
                
                // 2. Artists
                if !cachedArtists.isEmpty {
                    Section(header: sectionHeader(title: "Artists")) {
                        ForEach(cachedArtists, id: \.name) { artist in
                            NavigationLink(destination: SongCollectionDetailView(title: artist.name, songs: artist.songs, playerManager: playerManager, bookmarkManager: bookmarkManager, context: .artist(name: artist.name))) {
                                HStack(spacing: 12) {
                                    if let firstSong = artist.songs.first,
                                       let data = firstSong.artworkData,
                                       let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 44, height: 44)
                                            .clipShape(Circle())
                                    } else {
                                        ZStack {
                                            Circle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: "music.mic")
                                                .foregroundColor(.white)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(artist.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text("\(artist.count) songs")
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(.gray)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                                .background(Color.offlineBackground)
                                .contentShape(Rectangle())
                            }

                            Divider().background(Color.gray.opacity(0.1)).padding(.leading, 72)
                        }
                    }
                }
                
                // 3. Albums
                if !cachedAlbums.isEmpty {
                    Section(header: sectionHeader(title: "Albums")) {
                        ForEach(cachedAlbums, id: \.name) { album in
                            NavigationLink(destination: SongCollectionDetailView(title: album.name, songs: album.songs, playerManager: playerManager, bookmarkManager: bookmarkManager, context: .album(name: album.name))) {
                                HStack(spacing: 12) {
                                    if let first = album.songs.first, let data = first.artworkData, let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 44, height: 44)
                                            .cornerRadius(6)
                                            .clipped()
                                    } else {
                                        ZStack {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 44, height: 44)
                                                .cornerRadius(6)
                                            Image(systemName: "square.stack")
                                                .foregroundColor(.white)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(album.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text("\(album.count) songs")
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(.gray)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                                .background(Color.offlineBackground)
                                .contentShape(Rectangle())
                            }

                            Divider().background(Color.gray.opacity(0.1)).padding(.leading, 72)
                        }
                    }
                }
                
                // 4. Songs (already filtered by bookmarkManager)
                if !bookmarkManager.filteredSongs.isEmpty {
                    Section(header: sectionHeader(title: "Songs")) {
                        ForEach(bookmarkManager.filteredSongs) { song in
                            Button(action: {
                                playerManager.play(song: song, queue: bookmarkManager.filteredSongs, context: .allSongs)
                            }) {
                                SongRowContent(song: song, playerManager: playerManager, bookmarkManager: bookmarkManager, context: .allSongs)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button {
                                    activeSheet = .addToPlaylist(song)
                                } label: { Label("Add to Playlist", systemImage: "plus.circle") }
                                
                                Button {
                                    activeSheet = .itemStats(context: .song(song))
                                } label: {
                                    Label("Details", systemImage: "info.circle")
                                }
                            }
                            Divider().background(Color.gray.opacity(0.1)).padding(.leading, 72)
                        }
                    }
                }
            } // End else
            }
            .padding(.bottom, 150)
            .padding(.top, 10)
        }
    }
    
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.offlineBackground) // Opaque background for sticky header
    }
    
    @ViewBuilder
    private func searchResultFooter(filtered: Int, total: Int) -> some View {
        if !bookmarkManager.searchText.isEmpty {
            Text("Showing \(filtered) results of \(total)")
                .foregroundColor(.gray)
                .font(.system(size: 14))
                .padding(.top, 20)
                .padding(.bottom, 20)
        }
    }
    
    var albumsView: some View {
        // Use the computed property which handles filtering and sorting
        let allAlbums = cachedAlbums
        
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(allAlbums, id: \.name) { album in
                    NavigationLink(destination: SongCollectionDetailView(title: album.name, songs: album.songs, playerManager: playerManager, bookmarkManager: bookmarkManager, context: .album(name: album.name))) {
                        HStack(spacing: 12) {
                            if let first = album.songs.first, let data = first.artworkData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44) // Match songsView size (was 50)
                                    .cornerRadius(6)
                                    .clipped()
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 44, height: 44) // Match songsView size (was 50)
                                        .cornerRadius(6)
                                    Image(systemName: "square.stack")
                                        .foregroundColor(.white)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name.isEmpty ? "Unknown Album" : album.name)
                                    .font(.system(size: 15, weight: .medium)) // Match songsView
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(album.count) songs")
                                    .font(.system(size: 13)) // Match songsView
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color.offlineBackground)
                        .contentShape(Rectangle())
                    }

                    
                    Divider()
                        .background(Color.gray.opacity(0.1))
                        .padding(.leading, 72)
                }
                searchResultFooter(filtered: allAlbums.count, total: totalAlbumsCount)
            }
            .padding(.bottom, 150)
            .padding(.top, 10)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    

    
    private func getArtists(from songs: [Song]) -> [(name: String, count: Int, songs: [Song])] {
        var separatedArtists: [String: [Song]] = [:]
        let separators = CharacterSet(charactersIn: ",&/")
        
        for song in songs {
            // Check for anomalies first
            if song.artist.localizedCaseInsensitiveContains("Tyler, The Creator") {
                 // Handle Tyler specifically
                 // We need to be careful not to split him.
                 // Simplest way: Temporary placeholder or check if the full string is just him
                 // If the artist string contains him, we treat him as one token.
                 
                 // Strategy: Replace anomaly with a placeholder, split, then put back.
                 let placeholder = "___TYLER___"
                 let tempArtistString = song.artist.replacingOccurrences(of: "Tyler, The Creator", with: placeholder, options: .caseInsensitive)
                 
                 let names = tempArtistString.components(separatedBy: separators)
                 for name in names {
                     var cleaned = name
                        .replacingOccurrences(of: "feat.", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "ft.", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                     
                     if cleaned == placeholder {
                         cleaned = "Tyler, The Creator"
                     }
                     
                     if !cleaned.isEmpty {
                         var list = separatedArtists[cleaned] ?? []
                         list.append(song)
                         separatedArtists[cleaned] = list
                     }
                 }
            } else {
                // Standard logic
                let names = song.artist.components(separatedBy: separators)
                for name in names {
                     let cleaned = name
                        .replacingOccurrences(of: "feat.", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "ft.", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                     
                     if !cleaned.isEmpty {
                         var list = separatedArtists[cleaned] ?? []
                         list.append(song)
                         separatedArtists[cleaned] = list
                     }
                }
            }
        }
        
        return separatedArtists
            .map { (key, value) -> (name: String, count: Int, songs: [Song], duration: TimeInterval) in
                // Optimization: Calculate duration from the grouped songs directly
                // This avoids the O(N) filter in StatsManager for every artist
                // StatsManager.getDuration(for: Song) is O(1) dictionary lookup
                let duration = value.reduce(0) { $0 + StatsManager.shared.getDuration(for: $1) }
                return (name: key, count: value.count, songs: value, duration: duration)
            }
            .sorted {
                if $0.duration == $1.duration {
                    return $0.name < $1.name
                }
                return $0.duration > $1.duration
            }
            .map { (name: $0.name, count: $0.count, songs: $0.songs) }
    }

    var artistsView: some View {
        let allArtists = cachedArtists
        
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(allArtists, id: \.name) { artist in
                    NavigationLink(destination: SongCollectionDetailView(title: artist.name, songs: artist.songs, playerManager: playerManager, bookmarkManager: bookmarkManager, context: .artist(name: artist.name))) {
                        HStack(spacing: 12) {
                            if let firstSong = artist.songs.first,
                               let data = firstSong.artworkData,
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44) // Match songsView size (was 50)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 44, height: 44) // Match songsView size (was 50)
                                    Image(systemName: "music.mic")
                                        .foregroundColor(.white)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name.isEmpty ? "Unknown Artist" : artist.name)
                                    .font(.system(size: 15, weight: .medium)) // Match songsView
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(artist.count) songs")
                                    .font(.system(size: 13)) // Match songsView
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color.offlineBackground)
                        .contentShape(Rectangle())
                    }


                    
                    Divider()
                        .background(Color.gray.opacity(0.1))
                        .padding(.leading, 72)
                }
                searchResultFooter(filtered: allArtists.count, total: totalArtistsCount)
            }
            .padding(.bottom, 150)
            .padding(.top, 10)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    
    var playlistsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {

                
                 // Create Playlist Button
                Button(action: {
                    activeSheet = .createPlaylist
                }) {
                    HStack {
                        Image(systemName: "plus.square.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.offlineOrange)
                        Text("Create New Playlist")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(Color.offlineDarkGray)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .padding(.top, 12)
                
                ForEach(filteredPlaylists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist, bookmarkManager: bookmarkManager, playerManager: playerManager)) {
                        HStack(spacing: 12) {
                            ZStack {
                                if let data = playlist.coverArtData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipped()
                                        .cornerRadius(6)
                                } else {
                                    if let hex = playlist.colorHex {
                                        Rectangle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 44, height: 44)
                                            .cornerRadius(6)
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 44, height: 44)
                                            .cornerRadius(6)
                                    }
                                    if let emoji = playlist.iconEmoji {
                                        Text(emoji)
                                            .font(.title3)
                                    } else {
                                        Image(systemName: "music.note.list")
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.system(size: 15, weight: .medium)) // Match songsView
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(playlist.songPaths.count) songs")
                                    .font(.system(size: 13)) // Match songsView
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color.offlineBackground)
                        .contentShape(Rectangle())
                    }
                    .contextMenu {
                         Button(role: .destructive) {
                             bookmarkManager.deletePlaylist(playlist)
                         } label: {
                             Label("Delete Playlist", systemImage: "trash")
                         }
                        
                        Button {
                            activeSheet = .itemStats(context: .playlist(playlist))
                        } label: {
                            Label("Details", systemImage: "info.circle")
                        }
                    }
                    
                    Divider()
                         .background(Color.gray.opacity(0.1))
                         .padding(.leading, 72)
                }
                searchResultFooter(filtered: filteredPlaylists.count, total: bookmarkManager.playlists.count)
            }
            .padding(.bottom, 150)
            .padding(.top, 0)
            .padding(.top, 0)
        }
        .scrollDismissesKeyboard(.interactively)
    }


}

struct ChipView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .gray)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.offlineOrange : Color.offlineDarkGray)
                .cornerRadius(20)
        }
    }
}

struct AddToPlaylistView: View {
    @ObservedObject var bookmarkManager: BookmarkManager
    var song: Song?
    @Binding var isShowing: Bool
    @State private var showCreateSheet = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                List {
                    Section(header: Text("Create").foregroundColor(.gray).padding(.top, 16)) {
                        Button(action: {
                            showCreateSheet = true
                        }) {
                            Label("New Playlist", systemImage: "plus")
                                .foregroundColor(.offlineOrange)
                        }
                    }
                    .listRowBackground(Color.offlineDarkGray)
                    
                    Section(header: Text("Playlists").foregroundColor(.gray)) {
                        ForEach(bookmarkManager.playlists) { playlist in
                            Button(action: {
                                if let song = song {
                                    bookmarkManager.addToPlaylist(playlist: playlist, song: song)
                                }
                                isShowing = false
                            }) {
                                Text(playlist.name)
                                    .foregroundColor(.primary)
                            }
                        }
                        .listRowBackground(Color.offlineDarkGray)
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") { isShowing = false }.foregroundColor(.white))
            .sheet(isPresented: $showCreateSheet) {
                CreatePlaylistView(
                    bookmarkManager: bookmarkManager,
                    isPresented: $showCreateSheet,
                    songToAdd: song,
                    onPlaylistCreated: { _ in
                        isShowing = false
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    var bookmarkManager: BookmarkManager
    @Binding var activeSheet: ActiveSheet?
    var initialDirectory: URL? = nil
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false) // Import as reference
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        // REMOVED: picker.directoryURL assignment to prevent sandbox errors.
        // if let initialDirectory = initialDirectory {
        //    picker.directoryURL = initialDirectory
        // }
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: FolderPicker
        
        init(_ parent: FolderPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.activeSheet = nil // Explicitly dismiss sheet state
            
            // Small delay to allow sheet to animate out before alert triggers
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.parent.bookmarkManager.analyzePendingFolder(url: url)
            }
        }
    }
}

struct CreatePlaylistView: View {
    @ObservedObject var bookmarkManager: BookmarkManager
    @Binding var isPresented: Bool
    // Optional song to add immediately after creation
    var songToAdd: Song? = nil
    var onPlaylistCreated: ((Playlist) -> Void)? = nil
    
    @ObservedObject var storeManager = StoreManager.shared
    
    @State private var name: String = ""
    @State private var selectedColorHex: String? = Playlist.availableColors.randomElement()
    @State private var selectedEmoji: String? = nil
    
    // Custom Cover
    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker = false
    
    // Premium Trigger
    @State private var showPaywall = false
    
    let colors: [String] = Playlist.availableColors
    
    let emojis: [String] = Playlist.availableEmojis
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Preview Section
                        VStack(spacing: 8) {
                            Text("Preview")
                                .foregroundColor(.gray)
                                .font(.caption)
                            
                            ZStack {
                                if let image = selectedImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipped()
                                } else if let hex = selectedColorHex {
                                    Rectangle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 100, height: 100)
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 100, height: 100)
                                }
                                
                                // Only show emoji overlay if no image is selected
                                if selectedImage == nil {
                                    if let emoji = selectedEmoji {
                                        Text(emoji)
                                            .font(.system(size: 50))
                                    } else {
                                        Image(systemName: "music.note.list")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .frame(width: 100, height: 100)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                        }
                        .padding(.top, 20)
                        
                        TextField("Playlist Name", text: $name)
                            .padding()
                            .background(Color.offlineDarkGray)
                            .cornerRadius(10)
                            .foregroundColor(.white)
                            .accentColor(.offlineOrange)
                        
                        // Colors
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Cover Color")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                if !storeManager.isPremium {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundColor(.offlineOrange)
                                }
                            }
                            .padding(.leading, 4)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(colors, id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: selectedColorHex == hex ? 3 : 0)
                                            )
                                            .opacity(storeManager.isPremium ? 1.0 : 0.5)
                                            .onTapGesture {
                                                if storeManager.isPremium {
                                                    selectedColorHex = hex
                                                    selectedImage = nil // Reset image if color picked
                                                } else {
                                                    showPaywall = true
                                                }
                                            }
                                    }
                                    
                                    // Clear option
                                    ZStack {
                                        Circle()
                                            .stroke(Color.gray, lineWidth: 2)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "xmark")
                                            .foregroundColor(.gray)
                                    }
                                    .onTapGesture {
                                        selectedColorHex = nil
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        
                        // Emojis
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Icon Emoji")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                if !storeManager.isPremium {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundColor(.offlineOrange)
                                }
                            }
                            .padding(.leading, 4)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(emojis, id: \.self) { emoji in
                                        Text(emoji)
                                            .font(.system(size: 30))
                                            .frame(width: 44, height: 44)
                                            .background(selectedEmoji == emoji ? Color.white.opacity(0.2) : Color.clear)
                                            .cornerRadius(22)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: selectedEmoji == emoji ? 2 : 0)
                                            )
                                            .opacity(storeManager.isPremium ? 1.0 : 0.5)
                                            .onTapGesture {
                                                if storeManager.isPremium {
                                                    selectedEmoji = emoji
                                                    selectedImage = nil // Reset image if emoji picked
                                                } else {
                                                    showPaywall = true
                                                }
                                            }
                                    }
                                    
                                    // Clear option
                                    ZStack {
                                        Circle()
                                            .stroke(Color.gray, lineWidth: 2)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "xmark")
                                            .foregroundColor(.gray)
                                    }
                                    .onTapGesture {
                                        selectedEmoji = nil
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        
                        // Upload Cover Art
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Custom Cover Image")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                if !storeManager.isPremium {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundColor(.offlineOrange)
                                }
                            }
                            .padding(.leading, 4)
                            
                            Button(action: {
                                if storeManager.isPremium {
                                    showImagePicker = true
                                } else {
                                    showPaywall = true
                                }
                            }) {
                                HStack {
                                    Image(systemName: "photo")
                                    Text("Upload Image")
                                }
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.offlineDarkGray)
                                .cornerRadius(10)
                                .opacity(storeManager.isPremium ? 1.0 : 0.5)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        let imageData: Data? = selectedImage?.jpegData(compressionQuality: 0.8)
                        
                        bookmarkManager.createPlaylist(name: name, colorHex: selectedColorHex, iconEmoji: selectedEmoji, coverArtData: imageData)
                        
                        if let last = bookmarkManager.playlists.last {
                             if let song = songToAdd {
                                 bookmarkManager.addToPlaylist(playlist: last, song: song)
                             }
                             onPlaylistCreated?(last) // Callback
                        }
                        
                        isPresented = false
                    }
                    .foregroundColor(.offlineOrange)
                    .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
}

struct SongRowContent: View {
    let song: Song
    @ObservedObject var playerManager: AudioPlayerManager
    @ObservedObject var bookmarkManager: BookmarkManager
    let context: PlaybackContext
    
    var body: some View {
        HStack(spacing: 12) {
            if let data = song.artworkData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .cornerRadius(6)
                    Image(systemName: "music.note")
                        .foregroundColor(.gray)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                if bookmarkManager.isLiked(song: song) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    Text(song.durationString)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background((playerManager.currentSong?.id == song.id && playerManager.currentContext == context) ? Color.offlineDarkGray : Color.offlineBackground)
        .contentShape(Rectangle())
    }
}
