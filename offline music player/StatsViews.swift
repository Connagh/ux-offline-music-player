import SwiftUI


enum StatsContext {
    case song(Song)
    case artist(name: String)
    case album(name: String)
    case playlist(Playlist)
}

struct StatsDetailView: View {
    let context: StatsContext
    let allSongs: [Song]
    @ObservedObject var statsManager = StatsManager.shared
    @ObservedObject var bookmarkManager: BookmarkManager
    @ObservedObject var playerManager: AudioPlayerManager
    @Environment(\.presentationMode) var presentationMode
    @State private var coverImage: UIImage?
    @State private var showRhythmGame = false
    
    var title: String {
        switch context {
        case .song(let song): return song.title
        case .artist(let name): return name
        case .album(let name): return name
        case .playlist(let playlist): return playlist.name
        }
    }
    
    var subtitle: String? {
        switch context {
        case .song(let song): return song.artist
        case .artist: return "Artist"
        case .album: return "Album"
        case .playlist: return "Playlist"
        }
    }
    
    var timeInterval: TimeInterval {
        switch context {
        case .song(let song):
            return statsManager.getDuration(for: song)
        case .artist(let name):
            return statsManager.getDuration(forArtist: name, allSongs: allSongs)
        case .album(let name):
            return statsManager.getDuration(forAlbum: name, allSongs: allSongs)
        case .playlist(let playlist):
            return statsManager.getDuration(forPlaylist: playlist, allSongs: allSongs)
        }
    }
    
    var timeString: String {
        StatsManager.shared.formattedTime(timeInterval)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Cover Art
                        if let uiImage = coverImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 250, height: 250)
                                .cornerRadius(12)
                                .shadow(radius: 10)
                                .padding(.top, 20)
                        } else if case .song(let song) = context {
                             // Fallback / Loading
                             if song.artworkData != nil {
                                 // Has art but not loaded yet
                                 ZStack {
                                     RoundedRectangle(cornerRadius: 12)
                                         .fill(Color.offlineDarkGray)
                                         .frame(width: 250, height: 250)
                                     ProgressView()
                                         .tint(.white)
                                 }
                                 .padding(.top, 20)
                             } else {
                                // No art
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.offlineDarkGray)
                                        .frame(width: 250, height: 250)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 80))
                                        .foregroundColor(.gray)
                                }
                                .padding(.top, 20)
                             }
                        } else {
                            // Non-song context fallback
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.offlineDarkGray)
                                    .frame(width: 250, height: 250)
                                Image(systemName: "music.note")
                                    .font(.system(size: 80))
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 20)
                        }
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 40)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Total Listening Time")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text(timeString)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.offlineDarkGray)
                    .cornerRadius(12)
                    
                    if case .song(let song) = context {
                        VStack(spacing: 8) {
                            Text("Audio Quality")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            HStack {
                                if let bitrate = song.bitrate {
                                    Text("\(bitrate / 1000) kbps")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                
                                if let sampleRate = song.sampleRate {
                                    if song.bitrate != nil {
                                        Text("•").foregroundColor(.gray)
                                    }
                                    
                                    // If > 48kHz, show decimal, else Int looks cleaner? User asked for Hz/kHz.
                                    // Usually 44100 -> 44.1 kHz. 48000 -> 48.0 kHz.
                                    Text(String(format: "%.1f kHz", sampleRate / 1000.0))
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                
                                HQBadge(song: song)
                                    .padding(.leading, 4)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.offlineDarkGray)
                        .cornerRadius(12)
                        
                        VStack(spacing: 12) {
                            Divider()
                                .background(Color.gray)
                                .padding(.vertical)
                            
                            Button(action: {
                                if playerManager.isPlaying {
                                    playerManager.pause()
                                }
                                showRhythmGame = true
                            }) {
                                HStack {
                                    Text("Perform this song")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.offlineOrange)
                                .cornerRadius(12)
                            }
                            .fullScreenCover(isPresented: $showRhythmGame) {
                                RhythmGameView(bookmarkManager: bookmarkManager, initialSong: song)
                            }
                            
                            Text("This will launch the song in rhythm game mode.")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text("Recommendation: Use device speakers or wired headphones to reduce latency caused by bluetooth.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadCover()
        }
    }
    
    private func loadCover() async {
        guard case .song(let song) = context, let data = song.artworkData else {
            return
        }
        
        // Decode and resize on background
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let uiImage = UIImage(data: data) else { return nil }
            // Optional: Resize if it's massive?
            // For now, just decoding off main thread is a huge win.
            return uiImage
        }.value
        
        await MainActor.run {
            withAnimation {
                self.coverImage = image
            }
        }
    }
}


struct GlobalStatsView: View {
    @ObservedObject var statsManager = StatsManager.shared
    @Binding var songs: [Song]
    @Binding var playlists: [Playlist]
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            if songs.isEmpty {
                                Text("Import and listen to your music to view insights about your listening.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            
                            Text("All insights are local to your device.")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        StatsSection(title: "Top Songs") {
                            let topSongs = statsManager.getTopSongs(allSongs: songs, count: 5)
                            if topSongs.isEmpty {
                                Text("Your top songs will appear here")
                                    .font(.callout)
                                    .italic()
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(Array(topSongs.enumerated()), id: \.element.song.id) { index, item in
                                    StatRow(rank: index + 1, title: item.song.title, subtitle: item.song.artist, duration: statsManager.formattedTime(item.duration), artworkData: item.song.artworkData)
                                }
                            }
                        }
                        
                        StatsSection(title: "Top Artists") {
                            let topArtists = statsManager.getTopArtists(allSongs: songs, count: 5)
                            if topArtists.isEmpty {
                                Text("Your top artists will appear here")
                                    .font(.callout)
                                    .italic()
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(Array(topArtists.enumerated()), id: \.element.name) { index, item in
                                    // Find representative song for artwork
                                    let artwork = songs.first(where: { $0.artist == item.name })?.artworkData
                                    StatRow(rank: index + 1, title: item.name, subtitle: nil, duration: statsManager.formattedTime(item.duration), artworkData: artwork)
                                }
                            }
                        }
                        
                        StatsSection(title: "Top Albums") {
                            let topAlbums = statsManager.getTopAlbums(allSongs: songs, count: 5)
                            if topAlbums.isEmpty {
                                Text("Your top albums will appear here")
                                    .font(.callout)
                                    .italic()
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(Array(topAlbums.enumerated()), id: \.element.name) { index, item in
                                    // Find representative song for artwork and artist name
                                    let representative = songs.first(where: { $0.album == item.name })
                                    let artwork = representative?.artworkData
                                    let artist = representative?.artist
                                    
                                    StatRow(rank: index + 1, title: item.name, subtitle: artist, duration: statsManager.formattedTime(item.duration), artworkData: artwork)
                                }
                            }
                        }
                        

                    }
                    .padding()
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct StatsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 1) {
                content
            }
            .background(Color.offlineDarkGray)
            .cornerRadius(12)
        }
    }
}

struct StatRow: View {
    let rank: Int
    let title: String
    let subtitle: String?
    let duration: String?
    let artworkData: Data?
    
    var body: some View {
        HStack(spacing: 12) {
            Text("#\(rank)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.offlineOrange)
                // Reduced width slightly to accommodate image
                .frame(width: 25, alignment: .leading)
            
            // Cover Art
            if let artworkData = artworkData, let uiImage = UIImage(data: artworkData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
                    .clipped()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let duration = duration {
                Text(duration)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8) // Reduced vertical padding slightly for denser list
        .background(Color.offlineDarkGray)
    }
}
