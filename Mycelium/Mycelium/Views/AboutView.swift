import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showRecovery = false
    @State private var showRestore = false
    @State private var restoreInput = ""
    @State private var restoreMessage = ""
    @State private var restoreOK = false
    
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

                        Divider()
                            .padding(.vertical, 4)

                        Text("Your Identity")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        if let addr = IdentityManager.shared.address {
                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = addr
                                #else
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(addr, forType: .string)
                                #endif
                            } label: {
                                HStack {
                                    Text(addr)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                                }
                            }
                            .buttonStyle(.plain)
                            if let h = IdentityManager.shared.handle, !h.isEmpty {
                                Text("@\(h)")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                            }

                            // Key backup — the identity has no server escrow, so this
                            // recovery phrase is the ONLY way to restore it on another
                            // device or after reinstall. Hidden behind a tap.
                            DisclosureGroup(isExpanded: $showRecovery) {
                                if let phrase = IdentityManager.shared.currentMnemonic() {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("⚠️ Write these 24 words down and keep them private. Anyone with them controls your identity. There is no other way to recover it.")
                                            .font(.system(size: 11))
                                            .foregroundColor(Color(red: 0.6, green: 0.3, blue: 0.1))
                                        Text(phrase)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                                            .textSelection(.enabled)
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(red: 0.93, green: 0.92, blue: 0.89))
                                            .cornerRadius(8)
                                        Button {
                                            #if os(iOS)
                                            UIPasteboard.general.string = phrase
                                            #else
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(phrase, forType: .string)
                                            #endif
                                        } label: {
                                            Label("Copy recovery phrase", systemImage: "doc.on.doc")
                                                .font(.system(size: 12))
                                                .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 6)
                                }
                            } label: {
                                Label("Back up your identity", systemImage: "key.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                            }
                            .tint(Color(red: 0.55, green: 0.37, blue: 0.24))

                            // Restore — enter a recovery phrase from another device (e.g.
                            // your iPhone) to use the SAME identity here. Replaces the
                            // current identity on this device.
                            DisclosureGroup(isExpanded: $showRestore) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Enter your 24-word recovery phrase to restore an identity from another device. This replaces the identity currently on this device.")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                    TextEditor(text: $restoreInput)
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(height: 70)
                                        .padding(6)
                                        .background(Color(red: 0.93, green: 0.92, blue: 0.89))
                                        .cornerRadius(8)
                                        #if os(iOS)
                                        .autocorrectionDisabled(true)
                                        .textInputAutocapitalization(.never)
                                        #endif
                                    if !restoreMessage.isEmpty {
                                        Text(restoreMessage)
                                            .font(.system(size: 11))
                                            .foregroundColor(restoreOK ? .green : Color(red: 0.7, green: 0.2, blue: 0.1))
                                    }
                                    Button {
                                        let words = restoreInput
                                            .lowercased()
                                            .split(whereSeparator: { $0 == " " || $0 == "\n" })
                                            .map(String.init)
                                        guard words.count == 24 else {
                                            restoreOK = false
                                            restoreMessage = "Expected 24 words, got \(words.count)."
                                            return
                                        }
                                        if IdentityManager.shared.restore(mnemonic: words.joined(separator: " ")) {
                                            restoreOK = true
                                            restoreMessage = "✅ Identity restored. Restart the app to reconnect."
                                            restoreInput = ""
                                        } else {
                                            restoreOK = false
                                            restoreMessage = "Invalid recovery phrase. Check the words and try again."
                                        }
                                    } label: {
                                        Label("Restore identity", systemImage: "arrow.clockwise")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 6)
                            } label: {
                                Label("Restore a different identity", systemImage: "arrow.down.circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                            }
                            .tint(Color(red: 0.55, green: 0.37, blue: 0.24))
                        } else {
                            Text("Not yet initialized")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        }
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
