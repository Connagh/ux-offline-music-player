import SwiftUI

struct EffectsView: View {
    @ObservedObject var playerManager: AudioPlayerManager
    @ObservedObject var storeManager = StoreManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var showPaywall = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.offlineBackground.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 24) {
                    
                    // Header Spacer
                     Spacer().frame(height: 10)
                    
                    // 3D Audio Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Spatial Audio")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        Toggle(isOn: binding3D) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.offlineDarkGray)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "headphones")
                                        .font(.system(size: 16))
                                        .foregroundColor(.offlineOrange)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("3D Audio")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("A simple stereo widening effect that adds a sense of depth to the audio.")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .offlineOrange))
                        .padding()
                        .background(Color.offlineDarkGray.opacity(0.3))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
                    
                    // Filters Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Filters")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        Toggle(isOn: bindingNightcore) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.offlineDarkGray)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 16))
                                        .foregroundColor(.offlineOrange)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nightcore")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Speed up & Pitch up (1.25x)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .offlineOrange))
                        .padding()
                        .background(Color.offlineDarkGray.opacity(0.3))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Done Button
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Done")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.offlineOrange)
                        .cornerRadius(25)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
    
    // Binding that intercepts changes to check premium
    var binding3D: Binding<Bool> {
        Binding(
            get: { playerManager.is3DAudioEnabled },
            set: { newValue in
                if storeManager.isPremium {
                    playerManager.is3DAudioEnabled = newValue
                } else {
                    // Revert visual toggle if not premium (handled by not setting true)
                    // and show paywall
                    showPaywall = true
                }
            }
        )
    }

    
    var bindingNightcore: Binding<Bool> {
        Binding(
            get: { playerManager.isNightcoreActive },
            set: { newValue in
                if storeManager.isPremium {
                    playerManager.isNightcoreActive = newValue
                } else {
                    showPaywall = true
                }
            }
        )
    }
}
