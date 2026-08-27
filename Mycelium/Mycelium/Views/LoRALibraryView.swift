import SwiftUI

struct LoRALibraryView: View {
    @Environment(\.loraManager) var loraManager
    @Environment(\.llamaEngine) var engine
    
    var body: some View {
        List {
            Section {
                if loraManager.installed.isEmpty {
                    HStack {
                        Image(systemName: "square.stack.3d.up.slash")
                            .foregroundColor(.secondary)
                        Text("No adapters installed yet")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(Array(loraManager.installed.enumerated()), id: \.element.hash) { idx, lora in
                        InstalledLoRARow(lora: lora) {
                            if lora.isActive {
                                loraManager.deactivate(lora: lora, engine: engine)
                            } else {
                                loraManager.activate(lora: lora, engine: engine)
                            }
                        } onDelete: {
                            loraManager.delete(lora: lora, engine: engine)
                        }
                    }
                }
            } header: {
                Text("Installed")
                    .font(.system(.caption, design: .monospaced))
            } footer: {
                if !loraManager.installed.isEmpty {
                    Button {
                        for lora in loraManager.installed {
                            loraManager.delete(lora: lora, engine: engine)
                        }
                    } label: {
                        Text("Delete All")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Section {
                if loraManager.available.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Discovering peers…")
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                } else {
                    ForEach(loraManager.available) { lora in
                        AvailableLoRARow(lora: lora) {
                            // TODO: Request full adapter from peer via DERP/QUIC
                            print("lora: requesting \(lora.name) from peers")
                        }
                    }
                }
            } header: {
                Text("Available from Peers")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .navigationTitle("LoRA Library")
    }
}

struct InstalledLoRARow: View {
    let lora: LoRAInfo
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var showDisclaimer = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if lora.isLocal {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                }
                Text(lora.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Spacer()
                if !lora.isLocal {
                    Button(action: onToggle) {
                        Text(lora.isActive ? "Active" : "Load")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(lora.isActive ? Color.green.opacity(0.2) : Color.purple.opacity(0.2))
                            .foregroundColor(lora.isActive ? .green : .purple)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Your adapter")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.55, green: 0.37, blue: 0.24).opacity(0.15))
                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                        .cornerRadius(6)
                }
            }
            
            TagsRow(tags: lora.tags)
            
            HStack {
                if lora.isLocal {
                    Text("Trained \(formattedDate(lora.timestamp)) • \(lora.sizeMB) MB")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24).opacity(0.7))
                } else {
                    HStack {
                        Text("\(lora.sizeMB) MB • rank \(lora.rank) • by @\(lora.authorHandle)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        // Vote buttons + score
                        HStack(spacing: 8) {
                            Button {
                                NotificationCenter.default.post(name: .init("loraVote"), object: nil, userInfo: ["hash": lora.hash, "vote": "up"])
                            } label: {
                                Image(systemName: "hand.thumbsup")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Text("\(lora.score)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(lora.score > 0 ? .green : lora.score < 0 ? .red : .secondary)
                            
                            Button {
                                NotificationCenter.default.post(name: .init("loraVote"), object: nil, userInfo: ["hash": lora.hash, "vote": "down"])
                            } label: {
                                Image(systemName: "hand.thumbsdown")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                if lora.isLocal {
                    Spacer()
                    Text("Local only")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                if lora.sourceURL != nil {
                    Spacer()
                    Button {
                        showDisclaimer = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "link")
                            Text("Source")
                        }
                        .font(.caption2)
                        .foregroundColor(.purple.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Publish button for locally trained adapters
            if lora.isLocal {
                VStack(spacing: 6) {
                    // Test button — opens Test & Rate chat
                    Button {
                        NotificationCenter.default.post(
                            name: .init("openTestChat"),
                            object: nil,
                            userInfo: ["hash": lora.hash, "name": lora.name]
                        )
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                            Text("Test & Rate")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    // Publish button — requires 10+ ratings
                    let ratingCount = UserDefaults.standard.integer(forKey: "ratings_\(lora.hash)")
                    if ratingCount >= 10 {
                        Button {
                            NotificationCenter.default.post(
                                name: .init("publishLoRAFromLibrary"),
                                object: nil,
                                userInfo: ["hash": lora.hash]
                            )
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("Publish to Spore Network")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.55, green: 0.37, blue: 0.24).opacity(0.15))
                            .foregroundColor(Color(red: 0.55, green: 0.37, blue: 0.24))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "lock")
                                .font(.caption2)
                            Text("Rate \(max(0, 10 - ratingCount)) more responses to unlock publishing")
                                .font(.caption2)
                        }
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            if !lora.isLocal {
                Button {
                    NotificationCenter.default.post(name: .init("loraReport"), object: nil, userInfo: ["hash": lora.hash])
                } label: {
                    Label("Report", systemImage: "flag")
                }
                .tint(.orange)
                Button {
                    NotificationCenter.default.post(name: .init("loraBlock"), object: nil, userInfo: ["pubkey": lora.authorPubkey, "hash": lora.hash])
                } label: {
                    Label("Block", systemImage: "hand.raised")
                }
                .tint(.red)
            }
        }
        .alert("Content Source", isPresented: $showDisclaimer) {
            if let urlStr = lora.sourceURL, let url = URL(string: urlStr) {
                Button("Visit Source") {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #else
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("This adapter was trained on content from \(lora.sourceURL ?? "a third-party source"). Mycelium does not guarantee that responses accurately represent the original publisher's content. Visit the source for authoritative information.")
        }
    }
    
    private func formattedDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct AvailableLoRARow: View {
    let lora: LoRAInfo
    let onDownload: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(lora.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                TagsRow(tags: lora.tags)
                Text("\(lora.sizeMB) MB • by @\(lora.authorHandle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct TagsRow: View {
    let tags: [String]
    
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
            }
        }
    }
}

/// Simple wrapping flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
