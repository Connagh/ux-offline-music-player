import SwiftUI

struct ChangelogView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // NOTE: This text must be manually updated when CHANGELOG.md is updated.
    // Last Updated: 1.0.12
    let changelogText = """
    # Changelog
    
    All notable changes to this project will be documented in this file.
    
    ## Current Version: 1.0.12
    
    ## [1.0.12] - 2025-12-23
    ### Added
    - Expanded loading overlay to cover **App Launch** ("Loading Library..."), **Music Import**, and **Rescan Library** with "Scanning X of Y" progress.
    - Improved overlay visibility over existing menus (e.g. Settings).
    - Implemented forced re-import when rescanning to ensure all file changes (edits, deletions) are captured.
    - Suppressed false positive "[WARN] Failed to access security scoped resource" log during playback.
    - Added **"View Changelog"** button to Settings menu for easy access to update history.
    
    ## [1.0.11] - 2025-12-23
    ### Fixed
    - Fixed missing "Import from iCloud" confirmation prompt when adding folders via Settings.
    - Resolved "Resource deadlock avoided" error preventing playback of iCloud imported songs.
    
    ## [1.0.10] - 2025-12-22
    ### Changed
    - Updated "Pro" success screen to display "Music FX Filters".
    ### Fixed
    - Fixed bug where Paywall selection would persist incorrectly when buttons were tapped rapidly.
    - Added protection against multiple concurrent purchase requests.
    
    ## [1.0.9] - 2025-12-22
    ### Changed
    - Improved Paywall UI layout: Moved "14 Days Free Trial" text to avoid overcrowding.
    
    ## [1.0.8] - 2025-12-22
    ### Changed
    - Updated "Import Music" menu to dynamically display device name (e.g., "On My iPhone", "On My iPad").
    
    ## [1.0.7] - 2025-12-22
    ### Added
    - Added a "Rescan Library" button in Settings to manually detect new or deleted songs in imported folders.
    
    ## [1.0.6] - 2025-12-22
    ### Changed
    - Removed the 100 tiles per 60 seconds limit in Rhythm Game mode for unrestricted gameplay.
    
    ## [1.0.5] - 2025-12-22
    ### Changed
    - Refactored Paywall purchase buttons to prevent potential product mix-up (Lifetime vs Yearly).
    - Ensured Settings version display reflects the latest build.
    
    ## [1.0.4] - 2025-12-22
    ### Changed
    - Updated In-App Purchase product descriptions for better clarity and App Store compliance.
    - Finalized product IDs for production release.
    
    ## [1.0.3] - 2025-12-22
    ### Fixed
    - Fixed critical configuration issue where TestFlight builds were using local StoreKit file instead of App Store Connect.
    - Resolved "No products found" error for production builds.
    - Updated Product IDs to match App Store Connect format (removed `com` prefix).
    
    ## [1.0.2] - 2025-12-22
    ### Internal
    - Synchronized versioning for TestFlight distribution.
    
    ## [1.0.1] - 2025-12-22
    ### Fixed
    - Fixed "No products found" error in Paywall by adding retry logic.
    - Added connection error handling for In-App Purchases.
    
    ## [1.0.0] - 2025-12-20
    ### Added
    - Initial Release of the offline music player.
    - Features: Local file import, Equalizer, Rhythm Game, 3D Audio (Pro).
    """
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedStringKey(changelogText))
                        .font(.body)
                        .foregroundColor(.white)
                        .padding()
                }
            }
            .background(Color.offlineDarkGray.edgesIgnoringSafeArea(.all))
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.offlineOrange)
                }
            }
        }
    }
}
