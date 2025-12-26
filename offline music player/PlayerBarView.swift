import SwiftUI

struct PlayerBarView: View {
    @ObservedObject var playerManager: AudioPlayerManager
    @ObservedObject var bookmarkManager: BookmarkManager
    @ObservedObject var storeManager = StoreManager.shared
    
    // Volume state (simulated UI only for now as MPVolumeView is tricky in SwiftUI previews/tricks)
    // In a real app we might bind to system volume or internal player volume.
    @State private var volume: Float = 0.8
    @State private var isShowingAddToPlaylist = false
    @State private var showPaywall = false
    @State private var showEqualizer = false

    @State private var showGameAlert = false
    @State private var isGamePresented = false
    @State private var showEffectsView = false

    
    // Scrubbing State
    @State private var isDragging: Bool = false
    @State private var dragTime: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Progress Bar (Scrubbable)
            if let song = playerManager.currentSong, song.duration > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Clear touch buffer (captures touches)
                        Rectangle()
                            .fill(Color.black.opacity(0.001))
                            .frame(height: 18)
                        
                        // Background Track
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 2)
                        
                        // Active Progress
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: geo.size.width * CGFloat((isDragging ? dragTime : playerManager.currentTime) / song.duration), height: 2)
                    }
                    .contentShape(Rectangle()) // Ensure the whole area is tappable
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let percentage = value.location.x / geo.size.width
                                dragTime = Double(percentage) * song.duration
                                dragTime = max(0, min(dragTime, song.duration))
                            }
                            .onEnded { _ in
                                playerManager.seek(to: dragTime)
                                isDragging = false
                            }
                    )
                }
                .frame(height: 18) // Increased height for touch target (2px visible + 16px buffer)
                .padding(.bottom, -8) // Pull content up slightly to offset the buffer if needed, or just let it be taller.
                // Actually, let's not pull it up, let the bar be taller to prevent accidental clicks below.
            }
            
            VStack(spacing: 0) {
                HStack {
                // Song Info with Artwork
                if let song = playerManager.currentSong {
                    HStack(spacing: 8) { // Tighter spacing for smaller art
                        // Artwork
                        if let data = song.artworkData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 24, height: 24) // 0.5x size
                                .cornerRadius(4)
                                .clipped()
                        } else {
                            ZStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 24, height: 24) // 0.5x size
                                    .cornerRadius(4)
                                Image(systemName: "music.note")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 13, weight: .regular)) // Smaller than headline
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                } else if bookmarkManager.isImporting && bookmarkManager.songs.isEmpty {
                     HStack(spacing: 8) {
                         RoundedRectangle(cornerRadius: 4)
                             .fill(Color.gray.opacity(0.3))
                             .frame(width: 24, height: 24)
                         
                         VStack(alignment: .leading, spacing: 4) {
                             RoundedRectangle(cornerRadius: 2)
                                 .fill(Color.gray.opacity(0.3))
                                 .frame(width: 80, height: 10)
                             RoundedRectangle(cornerRadius: 2)
                                 .fill(Color.gray.opacity(0.3))
                                 .frame(width: 50, height: 8)
                         }
                     }
                     .onAppear {
                         // Basic pulse animation handled by views if needed, or simple static gray for now
                     }
                }
                
                Spacer() // Pushes info left and button right
                
                // Likes Button
                if let song = playerManager.currentSong {
                    Button(action: {
                        bookmarkManager.toggleLike(song: song)
                    }) {
                        Image(systemName: bookmarkManager.isLiked(song: song) ? "heart.fill" : "heart")
                            .font(.system(size: 20))
                            .foregroundColor(bookmarkManager.isLiked(song: song) ? .red : .white)
                            .padding(.trailing, 12)
                    }
                }

                // Plus / Menu Button
                if playerManager.currentSong != nil {
                     Button(action: {
                         isShowingAddToPlaylist = true
                     }) {
                         Image(systemName: "plus.circle")
                             .font(.system(size: 22))
                             .foregroundColor(.white)
                             .padding(.leading, 0)
                     }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16) // Reduced from 32 (removed 16)
            .padding(.bottom, 4)
            
            // Bottom Row: Controls
            // Bottom Row: Controls
            ZStack {
                // Side Controls (Left/Right)
                HStack {
                     // Left Group
                     HStack(spacing: 8) {
                         // FX Button
                         Button(action: {
                             showEffectsView = true
                         }) {
                             Text("FX")
                                 .font(.system(size: 12, weight: .bold))
                                 .foregroundColor(.white)
                                 .padding(.horizontal, 8)
                                 .padding(.vertical, 4)
                                 .background(
                                     Capsule()
                                         .stroke(playerManager.is3DAudioEnabled || playerManager.isNightcoreActive ? Color.offlineOrange : Color.gray, lineWidth: 1)
                                 )
                                 .shadow(color: (playerManager.is3DAudioEnabled || playerManager.isNightcoreActive) ? Color.offlineOrange.opacity(0.6) : Color.clear, radius: 4)
                         }
                         .sheet(isPresented: $showEffectsView) {
                             EffectsView(playerManager: playerManager)
                         }
                         
                         // Shuffle Toggle
                         
                         // Shuffle Toggle
                         Button(action: {
                             playerManager.toggleShuffle()
                         }) {
                             Image(systemName: "shuffle")
                                 .font(.system(size: 14, weight: .bold))
                                 .foregroundColor(playerManager.isShuffleEnabled ? .white : .gray)
                                 .padding(.horizontal, 8)
                                 .padding(.vertical, 4)
                                 .background(
                                     Capsule()
                                         .stroke(playerManager.isShuffleEnabled ? Color.offlineOrange : Color.gray, lineWidth: 1)
                                 )
                                 .shadow(color: playerManager.isShuffleEnabled ? Color.offlineOrange.opacity(0.6) : Color.clear, radius: 4)
                         }
                     }
                    
                     Spacer()
                     
                     // Right Group: DJ + EQ
                     HStack(spacing: 8) {
                         
                         // EQ Button (Toggle Style)
                         Button(action: {
                             if storeManager.isPremium {
                                 showEqualizer = true
                             } else {
                                 showPaywall = true
                             }
                         }) {
                             Text("EQ")
                                 .font(.system(size: 12, weight: .bold))
                                 .foregroundColor(playerManager.isEQActive ? .white : .gray)
                                 .padding(.horizontal, 8)
                                 .padding(.vertical, 4)
                                 .background(
                                     Capsule()
                                         .stroke(playerManager.isEQActive ? Color.offlineOrange : Color.gray, lineWidth: 1)
                                 )
                                 .shadow(color: playerManager.isEQActive ? Color.offlineOrange.opacity(0.6) : Color.clear, radius: 4)
                         }

                            // Game Mode Button
                         if playerManager.showGameButton {
                             Button(action: {
                                 if storeManager.isPremium {
                                     showGameAlert = true
                                 } else {
                                     showPaywall = true
                                 }
                             }) {
                                 Image(systemName: "gamecontroller.fill")
                                     .font(.system(size: 14))
                                     .foregroundColor(.white)
                                     .padding(.horizontal, 8)
                                     .padding(.vertical, 4)
                                     .background(
                                         Capsule()
                                             .stroke(Color.gray, lineWidth: 1)
                                     )
                             }
                             .alert(isPresented: $showGameAlert) {
                                 Alert(
                                     title: Text("Perform this song? (Experimental Mode)"),
                                     message: Text("Recommendation: Use device speakers or wired headphones to reduce latency caused by bluetooth."),
                                     primaryButton: .default(Text("Perform")) {
                                         if playerManager.isPlaying {
                                             playerManager.pause()
                                         }
                                         isGamePresented = true
                                     },
                                     secondaryButton: .cancel()
                                 )
                             }
                             .fullScreenCover(isPresented: $isGamePresented) {
                                 if let song = playerManager.currentSong {
                                     RhythmGameView(bookmarkManager: bookmarkManager, initialSong: song)
                                 } else {
                                     RhythmGameView(bookmarkManager: bookmarkManager)
                                 }
                             }
                         }
                     }
                }
                 
                 // Center Group (Controls)
                 HStack(spacing: 24) {
                     IconButton(icon: "backward.end.fill", size: 16) {
                         playerManager.previous()
                     }
                     
                     Button(action: {
                         playerManager.togglePlayPause()
                     }) {
                         ZStack {
                             Circle()
                                  .fill(playerManager.isPlaying ? Color.offlineOrange : Color.offlineDarkGray)
                                  .frame(width: 35, height: 35)
                                  .shadow(color: (playerManager.isPlaying ? Color.offlineOrange.opacity(0.4) : Color.black.opacity(0.3)), radius: 5, x: 0, y: 3)
                             
                             Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                 .font(.system(size: 16))
                                 .foregroundColor(.white)
                         }
                     }
                     
                     IconButton(icon: "forward.end.fill", size: 16) {
                         playerManager.next()
                     }
                 }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .padding(.top, 4)
        }

            .background(
                Group {
                    if playerManager.isLiquidGlassEnabled {
                        ZStack {
                            // Base Blur
                            Rectangle()
                                .fill(.ultraThinMaterial)
                            
                            // Darker Tint
                            Rectangle()
                                .fill(Color.black.opacity(0.3))
                            
                            // Glossy Gradient
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.15),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.white.opacity(0.2)),
                            alignment: .top
                        )
                    } else {
                        // Solid Dark Grey (Original)
                        Color(red: 0.15, green: 0.14, blue: 0.13)
                    }
                }
                .edgesIgnoringSafeArea(.bottom)
            )
        // Sheet for Add to Playlist
        .sheet(isPresented: $isShowingAddToPlaylist) {
            if let song = playerManager.currentSong {
                AddToPlaylistView(bookmarkManager: bookmarkManager, song: song, isShowing: $isShowingAddToPlaylist)
            }
        }
        .sheet(isPresented: $showEqualizer) {
            EqualiserView(playerManager: playerManager)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        }
    }
}
