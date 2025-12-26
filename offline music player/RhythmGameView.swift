import SwiftUI

struct RhythmGameView: View {
    @StateObject private var gameManager = RhythmGameManager()
    @ObservedObject var bookmarkManager: BookmarkManager
    var initialSong: Song? = nil
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            switch gameManager.state {
            case .selectingSong:
                SongSelectionView(gameManager: gameManager, songs: bookmarkManager.songs)
                
            case .loading:
                LoadingView(progress: gameManager.loadingProgress, songTitle: gameManager.selectedSong?.title ?? "")

                
            case .playing, .paused:
                GameplayView(gameManager: gameManager)
                
            case .finished:
                ResultsView(gameManager: gameManager)
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            if let initial = initialSong, gameManager.state == .selectingSong {
                gameManager.selectSong(initial)
            }
        }
    }
}

// MARK: - Song Selection

struct SongSelectionView: View {
    @ObservedObject var gameManager: RhythmGameManager
    let songs: [Song]
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Text("🎮 RHYTHM GAME")
                        .font(.system(size: 32, weight: .black))
                        .foregroundColor(.white)
                    
                    Text("Select a song to play")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(songs) { song in
                                SongRowButton(song: song) {
                                    gameManager.selectSong(song)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct SongRowButton: View {
    let song: Song
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Album art
                if let artworkData = song.artworkData, let uiImage = UIImage(data: artworkData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.offlineDarkGray)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.gray)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "play.fill")
                    .foregroundColor(.offlineOrange)
            }
            .padding()
            .background(Color.offlineDarkGray)
            .cornerRadius(12)
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    let progress: Double
    let songTitle: String
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Analyzing rhythm...")
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text(songTitle)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Animated waveform
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { i in
                    Capsule()
                        .fill(Color.offlineOrange)
                        .frame(width: 4, height: CGFloat.random(in: 10...40))
                        .animation(
                            Animation.easeInOut(duration: 0.3)
                                .repeatForever()
                                .delay(Double(i) * 0.05),
                            value: progress
                        )
                }
            }
            .frame(height: 50)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .offlineOrange))
                .frame(width: 200)
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Gameplay View

struct GameplayView: View {
    @ObservedObject var gameManager: RhythmGameManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.black, Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                
                // Lane dividers
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { lane in
                        Rectangle()
                            .stroke(gameManager.laneColors[lane].opacity(0.3), lineWidth: 1)
                            .frame(width: geometry.size.width / 4)
                    }
                }
                
                // Tap zone line
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(height: 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * gameManager.tapZonePosition)
                
                // Tiles
                ForEach(gameManager.activeTiles) { tile in
                    TileView(
                        tile: tile,
                        color: gameManager.laneColors[tile.beat.lane],
                        laneWidth: geometry.size.width / 4
                    )
                    .position(
                        x: (CGFloat(tile.beat.lane) + 0.5) * geometry.size.width / 4,
                        y: tile.yPosition * geometry.size.height
                    )
                }
                
                // Tap zones (interactive)
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { lane in
                        TapZoneView(
                            lane: lane,
                            color: gameManager.laneColors[lane],
                            onTap: { gameManager.tapLane(lane) }
                        )
                        .frame(width: geometry.size.width / 4)
                    }
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height * gameManager.tapZonePosition)
                
                // Exit Button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            gameManager.exit()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .opacity(0.8)
                        }
                        .padding()
                    }
                    Spacer()
                }
                
                // HUD
                VStack {
                    HStack {
                        // Score
                        VStack(alignment: .leading) {
                            Text("SCORE")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("\(gameManager.score)")
                                .font(.title.bold())
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Hit feedback
                    if let accuracy = gameManager.lastHitAccuracy {
                        Text(accuracy == .perfect ? "PERFECT! \(gameManager.combo)x" : accuracy == .good ? "GOOD \(gameManager.combo)x" : "MISS")
                            .font(.title.bold())
                            .foregroundColor(accuracy.color)
                            .shadow(color: accuracy.color, radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                }
            }
        }
    }
}

struct TileView: View {
    let tile: GameTile
    let color: Color
    let laneWidth: CGFloat
    
    var body: some View {
        Circle()
            .fill(
                tile.isHit ? Color.white :
                tile.isMissed ? Color.gray.opacity(0.3) :
                color
            )
            .frame(width: 50, height: 50)
            .shadow(color: tile.isHit ? .white : color, radius: tile.isHit ? 15 : 5)
            .opacity(tile.isMissed ? 0.3 : 1)
    }
}

struct TapZoneView: View {
    let lane: Int
    let color: Color
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Circle()
            .fill(isPressed ? color : color.opacity(0.3))
            .frame(width: 60, height: 60)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 3)
            )
            .scaleEffect(isPressed ? 1.1 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onTap()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Results View

struct ResultsView: View {
    @ObservedObject var gameManager: RhythmGameManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 30) {
            Text("🎉 COMPLETE!")
                .font(.system(size: 36, weight: .black))
                .foregroundColor(.white)
            
            if let song = gameManager.selectedSong {
                Text(song.title)
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            
            // Score display
            VStack(spacing: 8) {
                Text("FINAL SCORE")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("\(gameManager.score)")
                    .font(.system(size: 60, weight: .black))
                    .foregroundColor(.offlineOrange)
            }
            
            // Stats
            HStack(spacing: 40) {
                StatBox(label: "Perfect", value: "\(gameManager.perfectHits)", color: .yellow)
                StatBox(label: "Good", value: "\(gameManager.goodHits)", color: .green)
                StatBox(label: "Miss", value: "\(gameManager.misses)", color: .red)
            }
            
            Text("Max Combo: \(gameManager.maxCombo)x")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            // Buttons
            HStack(spacing: 20) {
                Button(action: { gameManager.retry() }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Retry")
                    }
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(Color.offlineDarkGray)
                    .cornerRadius(25)
                }
                
                Button(action: {
                    gameManager.exit()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Exit")
                    }
                    .font(.headline.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(Color.offlineOrange)
                    .cornerRadius(25)
                }
            }
            .padding(.bottom, 50)
        }
        .padding()
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// Difficulty UI structures removed
