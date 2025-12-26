import SwiftUI

struct LoadingOverlay: View {
    @Binding var isPresented: Bool
    var title: String = "Loading..."
    var message: String? = nil
    
    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if let message = message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(30)
                .background(Color.offlineDarkGray)
                .cornerRadius(20)
                .shadow(radius: 20)
            }
            .transition(.opacity)
            .zIndex(100) // Ensure it stays on top
        }
    }
}
