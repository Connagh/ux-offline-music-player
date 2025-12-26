import SwiftUI

struct SongCollectionDetailView: View {
    let title: String
    let songs: [Song]
    @ObservedObject var playerManager: AudioPlayerManager
    @ObservedObject var bookmarkManager: BookmarkManager
    let context: PlaybackContext
    
    var body: some View {
        ZStack {
            Color.offlineBackground.edgesIgnoringSafeArea(.all)
            
            VStack {
                if songs.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No songs found")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(songs) { song in
                                Button(action: {
                                    playerManager.play(song: song, queue: songs, context: context)
                                }) {
                                    SongRowContent(song: song, playerManager: playerManager, bookmarkManager: bookmarkManager, context: context)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider()
                                    .background(Color.gray.opacity(0.1))
                                    .padding(.leading, 72)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 150)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
