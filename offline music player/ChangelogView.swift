import SwiftUI

struct ChangelogView: View {
    @Environment(\.presentationMode) var presentationMode
    
    /// Loads the changelog content from the bundled CHANGELOG.md file.
    /// Falls back to an error message if the file cannot be loaded.
    var changelogText: String {
        // Try to find CHANGELOG.md in the app bundle
        if let path = Bundle.main.path(forResource: "CHANGELOG", ofType: "md"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            // Remove the HTML comment block at the end (versioning guide)
            if let commentStart = content.range(of: "<!-- ") {
                return String(content[..<commentStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return content
        }
        return "# Changelog\n\nUnable to load changelog. Please check for updates on GitHub."
    }
    
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
