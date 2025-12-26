import SwiftUI


struct PlaylistDetailView: View {
    let playlist: Playlist
    @ObservedObject var bookmarkManager: BookmarkManager
    @ObservedObject var playerManager: AudioPlayerManager
    
    @State private var isEditing = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            Color.offlineBackground.edgesIgnoringSafeArea(.all)
            
            VStack {
                if bookmarkManager.getSongs(for: playlist).isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Empty Playlist")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text("Add songs from your library by long-pressing on a song.")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(bookmarkManager.getSongs(for: playlist)) { song in
                            Button(action: {
                                playerManager.play(song: song, queue: bookmarkManager.getSongs(for: playlist), context: .playlist(id: playlist.id))
                            }) {
                                SongRowContent(song: song, playerManager: playerManager, bookmarkManager: bookmarkManager, context: .playlist(id: playlist.id))
                            }
                            .listRowBackground((playerManager.currentSong?.id == song.id && playerManager.currentContext == .playlist(id: playlist.id)) ? Color.offlineDarkGray : Color.offlineBackground)
                            .contextMenu {
                                Button(role: .destructive) {
                                    bookmarkManager.removeFromPlaylist(playlist: playlist, song: song)
                                } label: {
                                    Label("Remove from Playlist", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isEditing = true }) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.offlineOrange)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditPlaylistView(bookmarkManager: bookmarkManager, playlist: playlist, isPresented: $isEditing)
        }
        .onChange(of: bookmarkManager.playlists) {
            // If playlist no longer exists, pop back
            if !bookmarkManager.playlists.contains(where: { $0.id == playlist.id }) {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

struct EditPlaylistView: View {
    @ObservedObject var bookmarkManager: BookmarkManager
    let playlist: Playlist
    @ObservedObject var storeManager = StoreManager.shared
    
    @Binding var isPresented: Bool
    
    @State private var name: String
    @State private var selectedColorHex: String?
    @State private var selectedEmoji: String?
    
    // Custom Cover
    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker = false
    
    // Premium Trigger
    @State private var showPaywall = false
    @State private var showDeleteConfirmation = false
    
    let colors: [String] = Playlist.availableColors
    
    let emojis: [String] = Playlist.availableEmojis
    
    init(bookmarkManager: BookmarkManager, playlist: Playlist, isPresented: Binding<Bool>) {
        self.bookmarkManager = bookmarkManager
        self.playlist = playlist
        self._isPresented = isPresented
        self._name = State(initialValue: playlist.name)
        self._selectedColorHex = State(initialValue: playlist.colorHex)
        self._selectedEmoji = State(initialValue: playlist.iconEmoji)
        
        if let data = playlist.coverArtData, let image = UIImage(data: data) {
             self._selectedImage = State(initialValue: image)
        }
    }
    
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
                                     Text(selectedImage == nil ? "Upload Image" : "Change Image")
                                 }
                                 .foregroundColor(.white)
                                 .padding()
                                 .frame(maxWidth: .infinity)
                                 .background(Color.offlineDarkGray)
                                 .cornerRadius(10)
                                 .opacity(storeManager.isPremium ? 1.0 : 0.5)
                             }
                             
                             if selectedImage != nil {
                                 Button(role: .destructive) {
                                     selectedImage = nil
                                 } label: {
                                     Text("Remove Custom Cover")
                                         .font(.caption)
                                         .foregroundColor(.red)
                                         .padding(.top, 4)
                                 }
                             }
                         }
                         

                          // Delete Playlist Button
                          Button(action: {
                              showDeleteConfirmation = true
                          }) {
                              Text("Delete Playlist")
                                  .foregroundColor(.red)
                                  .padding()
                                  .frame(maxWidth: .infinity)
                                  .background(Color.offlineDarkGray)
                                  .cornerRadius(10)
                          }
                          .padding(.top, 16)
                          .alert(isPresented: $showDeleteConfirmation) {
                              Alert(
                                  title: Text("Delete Playlist?"),
                                  message: Text("Are you sure you want to delete '\(playlist.name)'? This action cannot be undone."),
                                  primaryButton: .destructive(Text("Delete")) {
                                      bookmarkManager.deletePlaylist(playlist)
                                      isPresented = false
                                  },
                                  secondaryButton: .cancel()
                              )
                          }
                          
                         Spacer()
                     }
                     .padding()
                 }
             }
             .navigationTitle("Edit Playlist")
             .navigationBarTitleDisplayMode(.inline)
             .toolbar {
                 ToolbarItem(placement: .navigationBarLeading) {
                     Button("Cancel") {
                         isPresented = false
                     }
                     .foregroundColor(.white)
                 }
                 
                 ToolbarItem(placement: .navigationBarTrailing) {
                     Button("Save") {
                         let imageData: Data? = selectedImage?.jpegData(compressionQuality: 0.8)
                         
                         bookmarkManager.updatePlaylist(playlist, newName: name, newColorHex: selectedColorHex, newIconEmoji: selectedEmoji, newCoverArt: imageData)
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



extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
