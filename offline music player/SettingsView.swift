import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var bookmarkManager: BookmarkManager
    @ObservedObject var playerManager: AudioPlayerManager
    @Environment(\.presentationMode) var presentationMode
    
    @ObservedObject var storeManager = StoreManager.shared
    @State private var showClearConfirmation = false
    @State private var showChangelog = false
    @State private var showPaywall = false
    @State private var showFolderPicker = false
    @State private var showInsights = false
    @State private var showImportOptions = false
    @State private var selectedImportURL: URL? = nil
    @State private var showEqualizer = false

    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                List {
                    // About section moved below per request (wait, request said "move unlock pro to top" AND "move about to top" previously.
                    // The latest request: "move the unlock pro section to the top of the settings page."
                    // Previously "About" was top. Current structure: About is top. User wants Unlock Pro top.
                    // So I swap About and Unlock Pro.
                    Section {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.offlineOrange)
                                .font(.title2)
                            
                            VStack(alignment: .leading) {
                                Text(storeManager.isPremium ? "Pro Unlocked" : "Unlock Pro")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                if !storeManager.isPremium {
                                    Text("Get access to all features")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                            
                            if !storeManager.isPremium {
                                Button("Upgrade") {
                                    showPaywall = true
                                }
                                .foregroundColor(.offlineBackground)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.offlineOrange)
                                .cornerRadius(15)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .sheet(isPresented: $showPaywall) {
                        PaywallView()
                    }
                    .sheet(isPresented: $showInsights) {
                        GlobalStatsView(songs: $bookmarkManager.songs, playlists: $bookmarkManager.playlists)
                    }
                    .sheet(isPresented: $showFolderPicker) {
                        SettingsFolderPicker(bookmarkManager: bookmarkManager, isPresented: $showFolderPicker, initialDirectory: selectedImportURL)
                    }
                    
                    Section(header: Text("About").foregroundColor(.gray)) {
                        Text("This app runs entirely offline. It streams music directly from your local files and does not connect to any servers.")
                            .foregroundColor(.white)
                            .font(.body)
                            .padding(.vertical, 4)
                            .listRowBackground(Color.offlineDarkGray)
                    }
                    

                    

                    
                    Section(header: Text("Imported Folders").foregroundColor(.gray).padding(.top, 16), footer: Text("Linked: Playing directly from original location.\nDownloaded: Saved offline from iCloud.").font(.caption).foregroundColor(.gray)) {
                        if bookmarkManager.folders.isEmpty {
                            Text("No folders added")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(bookmarkManager.folders) { folder in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(folder.url.lastPathComponent)
                                            .foregroundColor(.white)
                                            .font(.headline)
                                        
                                        HStack(spacing: 8) {
                                            // Location Badge
                                            HStack(spacing: 4) {
                                                Image(systemName: folder.isUbiquitous ? "icloud.and.arrow.down" : "link")
                                                    .font(.caption2)
                                                Text(folder.isUbiquitous ? "Downloaded" : "Linked")
                                                    .font(.caption2)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.gray.opacity(0.3))
                                            .cornerRadius(4)
                                            
                                            // Size Badge
                                            if folder.byteCount > 0 {
                                                Text(folder.sizeString)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Text("\(folder.songCount) songs")
                                        .foregroundColor(.offlineOrange)
                                        .font(.subheadline)
                                }
                                .listRowBackground(Color.offlineDarkGray)
                            }
                            .onDelete(perform: deleteFolder)
                        }
                        
                        Button(action: {
                            showImportOptions = true
                        }) {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                Text("Add Music Folder")
                            }
                            .foregroundColor(.offlineOrange)
                        }
                        .listRowBackground(Color.offlineDarkGray)
                        .confirmationDialog("Import Music", isPresented: $showImportOptions, titleVisibility: .visible) {
                            Button("Add a folder") {
                                selectedImportURL = nil
                                showFolderPicker = true
                            }
                            
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Add a music folder from 'On My iPhone' or 'iCloud Drive'.")
                        }
                        
                        if !bookmarkManager.folders.isEmpty {
                            Button(action: {
                                bookmarkManager.rescanAllFolders()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Rescan Library")
                                }
                                .foregroundColor(bookmarkManager.isImporting ? .gray : .white)
                            }
                            .disabled(bookmarkManager.isImporting)
                            .listRowBackground(Color.offlineDarkGray)
                        }
                    }
                    
                    Section(header: Text("Listening insights").foregroundColor(.gray)) {
                        Button(action: {
                            if storeManager.isPremium {
                                showInsights = true
                            } else {
                                showPaywall = true
                            }
                        }) {
                            HStack {
                                Text("Insights")
                                    .foregroundColor(.white)
                                Spacer()
                                if !storeManager.isPremium {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.offlineOrange)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                            }
                        }
                        .listRowBackground(Color.offlineDarkGray)
                    }
                    
                    Section(header: Text("Data").foregroundColor(.gray)) {

                        
                        Button(action: {
                            showClearConfirmation = true
                        }) {
                            Text("Clear Local Data")
                                .foregroundColor(.red)
                        }
                        .listRowBackground(Color.offlineDarkGray)
                        .alert(isPresented: $showClearConfirmation) {
                            Alert(
                                title: Text("Clear Local Data?"),
                                message: Text("This will remove all imported folders and songs from the library. This action cannot be undone."),
                                primaryButton: .destructive(Text("Clear All")) {
                                    clearAllData()
                                },
                                secondaryButton: .cancel()
                            )
                        }
                        

                    }
                    
                    Section(header: Text("Appearance").foregroundColor(.gray)) {
                        Toggle("Liquid Glass Player", isOn: $playerManager.isLiquidGlassEnabled)
                            .listRowBackground(Color.offlineDarkGray)
                            .foregroundColor(.white)
                    }

                    Section(header: Text("Audio Enhancements").foregroundColor(.gray)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Apple Spatial Audio")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            
                            Text("Requires supported Apple headphones (AirPods 3/4, Pro, Max) and compatible music files (supporting Dolby Atmos).")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Link("Learn more about Spatial Audio", destination: URL(string: "https://support.apple.com/en-us/HT212182")!)
                                .font(.caption)
                                .foregroundColor(.offlineOrange)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.offlineDarkGray)
                        


                        
                        // Equalizer Button
                        Button(action: {
                            if storeManager.isPremium {
                                showEqualizer = true
                            } else {
                                showPaywall = true
                            }
                        }) {
                            HStack {
                                Text("Equaliser")
                                    .foregroundColor(.white)
                                Spacer()
                                if !storeManager.isPremium {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.offlineOrange)
                                } else {
                                    Image(systemName: "slider.vertical.3")
                                        .foregroundColor(.offlineOrange)
                                }
                            }
                        }
                        .listRowBackground(Color.offlineDarkGray)
                        .sheet(isPresented: $showEqualizer) {
                            EqualiserView(playerManager: playerManager)
                        }
                        

                    }
                    
                    Section(header: Text("Player Controls").foregroundColor(.gray)) {
                        VStack(alignment: .leading, spacing: 4) {
                            if storeManager.isPremium {
                                Toggle(isOn: $playerManager.showGameButton) {
                                    Text("Show Game Button")
                                        .foregroundColor(.white)
                                }
                            } else {
                                Button(action: { showPaywall = true }) {
                                    HStack {
                                        Text("Show Game Button")
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.offlineOrange)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.offlineDarkGray)
                        

                    }
                    
                    

                    
                    Section(header: Text("View our source code").foregroundColor(.gray)) {
                        Button(action: {
                            showChangelog = true
                        }) {
                            HStack {
                                Text("View Changelog")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "doc.text")
                                    .foregroundColor(.offlineOrange)
                            }
                        }
                        .sheet(isPresented: $showChangelog) {
                            ChangelogView()
                        }
                        
                        Button(action: {
                            if let url = URL(string: "https://github.com/Connagh/ux-offline-music-player") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text("View on GitHub")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                            .foregroundColor(.offlineOrange)
                        }
                        .listRowBackground(Color.offlineDarkGray)
                    }
                    
                    Section(header: Text("Legal").foregroundColor(.gray)) {
                        Link(destination: URL(string: "https://gist.github.com/Connagh/ebad376564d253ed76d22c30c8bc4313")!) {
                            HStack {
                                Text("Privacy Policy")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.offlineOrange)
                            }
                        }
                        .listRowBackground(Color.offlineDarkGray)
                        
                        Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                            HStack {
                                Text("Terms of Use")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.offlineOrange)
                            }
                        }
                        .listRowBackground(Color.offlineDarkGray)
                    }
                    
                    Section {
                        VStack(spacing: 4) {
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(InsetGroupedListStyle())
                

                // Loading Overlay for Settings Context
                LoadingOverlay(
                    isPresented: $bookmarkManager.loadingState.isActive,
                    title: bookmarkManager.loadingState.title,
                    message: bookmarkManager.totalBatchSize > 0 ? "Scanning \(bookmarkManager.processedBatchCount) of \(bookmarkManager.totalBatchSize)" : nil
                )
            }
            .navigationTitle("Settings")
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
        .preferredColorScheme(.dark)
    }
    
    func deleteFolder(at offsets: IndexSet) {
        bookmarkManager.removeFolder(at: offsets)
        validateCurrentSong()
    }
    
    func clearAllData() {
        bookmarkManager.removeAll()
        playerManager.stop()
    }
    
    func validateCurrentSong() {
        // Check if the current song still exists in the list
        if let current = playerManager.currentSong {
            if !bookmarkManager.songs.contains(where: { $0.id == current.id }) {
                playerManager.stop()
            }
        }
    }
}

struct SettingsFolderPicker: UIViewControllerRepresentable {
    var bookmarkManager: BookmarkManager
    @Binding var isPresented: Bool
    var initialDirectory: URL? = nil
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
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
        var parent: SettingsFolderPicker
        
        init(_ parent: SettingsFolderPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.isPresented = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.parent.bookmarkManager.analyzePendingFolder(url: url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
