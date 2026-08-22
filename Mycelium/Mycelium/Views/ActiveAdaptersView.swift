import SwiftUI

/// A focused view showing only the currently active LoRA adapters.
/// Shown when tapping the brain counter in the toolbar.
struct ActiveAdaptersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.loraManager) var loraManager
    
    var body: some View {
        NavigationStack {
            let active = loraManager.installed.filter(\.isActive)
            
            if active.isEmpty {
                VStack(spacing: 12) {
                    Text("🧠")
                        .font(.system(size: 48))
                    Text("No adapters active")
                        .font(.headline)
                    Text("Adapters activate automatically when you ask a question that matches their knowledge area.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                List(active, id: \.hash) { lora in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lora.name)
                            .font(.headline)
                        if !lora.tags.isEmpty {
                            Text(lora.tags.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let source = lora.sourceURL, !source.isEmpty {
                            Link(source, destination: URL(string: source)!)
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        
            Spacer()
                .navigationTitle("Active Adapters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
