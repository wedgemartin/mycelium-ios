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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(lora.isActive ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(lora.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                TagsRow(tags: lora.tags)
                Text("\(lora.sizeMB) MB • rank \(lora.rank) • by @\(lora.authorHandle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
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
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
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
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
            }
        }
    }
}
