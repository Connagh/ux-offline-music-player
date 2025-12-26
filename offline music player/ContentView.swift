import SwiftUI

struct ContentView: View {
    @StateObject private var bookmarkManager = BookmarkManager()
    @StateObject private var playerManager = AudioPlayerManager()
    
    // Configure appearance for NavigationBar to match theme
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.offlineBackground)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        
        // Dark mode preference
        UIView.appearance().overrideUserInterfaceStyle = .dark
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Song List
            SongListView(bookmarkManager: bookmarkManager, playerManager: playerManager)
            
            PlayerBarView(playerManager: playerManager, bookmarkManager: bookmarkManager)
            
            // App-wide Loading Overlay
            LoadingOverlay(
                isPresented: $bookmarkManager.loadingState.isActive,
                title: bookmarkManager.loadingState.title,
                message: bookmarkManager.totalBatchSize > 0 ? "Scanning \(bookmarkManager.processedBatchCount) of \(bookmarkManager.totalBatchSize)" : nil
            )
        }
        .edgesIgnoringSafeArea(.bottom) // Allow player bar to sit at very bottom
        .preferredColorScheme(.dark)
        .onChange(of: bookmarkManager.isImporting) { _, isImporting in // Updated for iOS 17
            if !isImporting && !bookmarkManager.songs.isEmpty {
                // Determine if we should restore state.
                // We only want to do this once on launch.
                // Since isImporting might toggle multiple times if user adds folders later,
                // we should check if the player is already loaded or just rely on "first load".
                
                // For now, simpler retrieval: if player has NO current song, try restore.
                if playerManager.currentSong == nil {
                    playerManager.restoreLastState(from: bookmarkManager.songs)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
