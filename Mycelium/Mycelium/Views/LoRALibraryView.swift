import SwiftUI

struct LoRALibraryView: View {
    @State private var installedLoRAs: [LoRAInfo] = []
    @State private var availableLoRAs: [LoRAInfo] = [] // from peers
    
    var body: some View {
        List {
            Section("Installed") {
                if installedLoRAs.isEmpty {
                    Text("No LoRAs installed yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(installedLoRAs) { lora in
                        LoRARow(lora: lora, isInstalled: true)
                    }
                }
            }
            
            Section("Available from Peers") {
                if availableLoRAs.isEmpty {
                    Text("Discovering peers...")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(availableLoRAs) { lora in
                        LoRARow(lora: lora, isInstalled: false)
                    }
                }
            }
        }
        .navigationTitle("LoRA Library")
    }
}

struct LoRARow: View {
    let lora: LoRAInfo
    let isInstalled: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(lora.name)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    ForEach(lora.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                }
                Text("\(lora.sizeMB) MB • by \(lora.authorHandle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button {
                    // Download LoRA from peer
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.purple)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
