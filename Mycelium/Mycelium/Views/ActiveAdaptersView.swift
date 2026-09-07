import SwiftUI

/// A focused view showing only the currently active LoRA adapters.
/// Shown when tapping the brain counter in the toolbar.
struct ActiveAdaptersView: View {
    @Environment(\.dismiss) private var dismiss
    /// The live LoRAManager passed explicitly (reference type = always current).
    let loraManager: LoRAManager

    var body: some View {
        NavigationStack {
            Group {
                let active = loraManager.installed.filter(\.isActive)
                if active.isEmpty {
                    VStack(spacing: 12) {
                        Text("🧠").font(.system(size: 48))
                        Text("No adapters active")
                            .font(.headline)
                        Text("Adapters activate automatically when you ask a question that matches their knowledge area.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(active, id: \.hash) { lora in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lora.name)
                                        .font(.headline)
                                    if !lora.tags.isEmpty {
                                        Text(lora.tags.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let source = lora.sourceURL, !source.isEmpty,
                                       let url = URL(string: source) {
                                        Link(source, destination: url)
                                            .font(.caption2)
                                            .foregroundColor(.purple)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Divider()
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Active Adapters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}
