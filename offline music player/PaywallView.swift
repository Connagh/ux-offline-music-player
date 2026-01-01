import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var storeManager = StoreManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                if showSuccess {
                   FeaturesUnlockedView {
                       dismiss()
                   }
                   .transition(.opacity)
                } else {
                    ScrollView {
                        VStack(spacing: 25) {
                            // Header
                            VStack(spacing: 10) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.offlineOrange)
                                    .padding(.bottom, 10)
                                
                                Text("Unlock Pro")
                                    .font(.largeTitle)
                                    .bold()
                                    .foregroundColor(.white)
                                
                                Text("Get the ultimate offline music experience.")
                                    .font(.body)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.top, 40)
                            
                            // Features List
                            VStack(alignment: .leading, spacing: 20) {
                                FeatureRow(icon: "chart.bar.fill", title: "See your listening insights", description: "Get insight on your most listened songs, artist, and albums.")
                                FeatureRow(icon: "paintpalette.fill", title: "Customise your playlists", description: "Create or upload your own custom playlists art")
                                FeatureRow(icon: "slider.vertical.3", title: "Equaliser", description: "Fine-tune your audio with a 6-band EQ and presets.")
                                FeatureRow(icon: "gamecontroller.fill", title: "Rhythm Game", description: "Play along to your favorite songs.")
                                FeatureRow(icon: "headphones", title: "Audio Effects", description: "Unlock audio effects to experience your music in all new ways.")
                            }
                            .padding()
                            .background(Color.offlineDarkGray.opacity(0.5))
                            .cornerRadius(15)
                            .padding(.horizontal)
                            
                            Spacer()
                            
                            // Purchase Buttons
                            if !storeManager.products.isEmpty {
                                VStack(spacing: 12) {
                                    ForEach(storeManager.products) { product in
                                    PurchaseButton(storeManager: storeManager, product: product)
                                    }
                                }
                                .padding(.horizontal)
                            } else if storeManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                VStack(spacing: 12) {
                                    Text(storeManager.errorMessage ?? "Unable to load products.")
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    
                                    Button(action: {
                                        Task { await storeManager.requestProducts() }
                                    }) {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Retry")
                                        }
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 20)
                                        .background(Color.offlineDarkGray)
                                        .cornerRadius(8)
                                    }
                                }
                                .padding()
                            }
                            
                            // Restore
                            Button("Restore Purchases") {
                                Task { await storeManager.restorePurchases() }
                            }
                            .foregroundColor(.gray)
                            .font(.footnote)
                            .padding(.bottom, 10)
                            
                            // Legal Links (Required for App Store)
                            HStack(spacing: 16) {
                                Link("Privacy Policy", destination: URL(string: "https://gist.github.com/Connagh/ebad376564d253ed76d22c30c8bc4313")!)
                                Text("•")
                                    .foregroundColor(.gray)
                                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            }
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.bottom, 20)
                        }
                        .padding(.bottom, 20) // Extra padding for scroll
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !showSuccess {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                    } else {
                        Button("Close") {
                             dismiss()
                        }
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                    }
                }
            }
            .onChange(of: storeManager.isPremium) { _, isPremium in
                if isPremium {
                    withAnimation {
                         showSuccess = true
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            // Auto-retry fetching products if none are loaded when view appears
            if storeManager.products.isEmpty {
                await storeManager.requestProducts()
            }
        }
    }
}

// MARK: - Subviews

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.offlineOrange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(LocalizedStringKey(description))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct FeaturesUnlockedView: View {
    var onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .shadow(color: .green.opacity(0.5), radius: 10)
            
            VStack(spacing: 8) {
                Text("You're a Pro!")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                
                Text("Thank you for your support. You've unlocked:")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                UnlockedFeatureRow(text: "Listening Insights")
                UnlockedFeatureRow(text: "Custom Playlists Art")
                UnlockedFeatureRow(text: "6-Band Equaliser")
                UnlockedFeatureRow(text: "Rhythm Game Mode")
                UnlockedFeatureRow(text: "Music FX Filters")
            }
            .padding()
            .background(Color.offlineDarkGray.opacity(0.3))
            .cornerRadius(16)
            .padding(.horizontal, 30)
            
            Spacer()
            
            Button(action: onClose) {
                Text("Start Listening")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.offlineOrange)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }
}

struct UnlockedFeatureRow: View {
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: "lock.open.fill")
                .foregroundColor(.offlineOrange)
            Text(text)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
    }
}

struct PurchaseButton: View {
    @ObservedObject var storeManager: StoreManager
    let product: Product
    
    var body: some View {
        Button {
            Task {
                await storeManager.purchase(product)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    if let subscription = product.subscription, let intro = subscription.introductoryOffer {
                        if intro.paymentMode == .freeTrial {
                            Text("14 Days Free Trial")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundColor(.offlineOrange)
                }
            }
            .padding()
            .background(Color.offlineDarkGray)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.offlineOrange.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(storeManager.isPurchasing)
        .opacity(storeManager.isPurchasing ? 0.6 : 1.0)
    }
}
