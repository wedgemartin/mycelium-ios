import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120)
                        .padding(.top, 32)
                    
                    Text("Mycelium")
                        .font(.system(size: 28, design: .serif))
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    
                    Text("\(version) (\(build))")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("P2P on-device AI with shared LoRA adapters.")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        
                        Text("Mycelium runs a language model directly on your phone — no cloud, no API keys, no data leaving your device. Knowledge adapters propagate peer-to-peer through geographic gossip over the Spore protocol.")
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        FeatureRow(emoji: "🧠", text: "On-device inference via Metal GPU")
                        FeatureRow(emoji: "🍄", text: "LoRA adapters for specialized knowledge")
                        FeatureRow(emoji: "📡", text: "P2P adapter sharing over Spore network")
                        FeatureRow(emoji: "🔒", text: "Private by architecture — nothing leaves your device")
                        FeatureRow(emoji: "⚡", text: "Dynamic adapter routing per question")
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Link(destination: URL(string: "https://mycelium.getspore.xyz")!) {
                            Label("Website", systemImage: "globe")
                        }
                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                        
                        Link(destination: URL(string: "https://getspore.xyz")!) {
                            Label("Spore Protocol", systemImage: "network")
                        }
                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                        
                        Link(destination: URL(string: "https://mycelium.getspore.xyz/privacy.html")!) {
                            Label("Privacy Policy", systemImage: "lock.shield")
                        }
                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
            }
            .background(Color(red: 0.976, green: 0.965, blue: 0.949))
            .preferredColorScheme(.light)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let emoji: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 16))
            Text(text)
                .font(.subheadline)
                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
        }
    }
}
