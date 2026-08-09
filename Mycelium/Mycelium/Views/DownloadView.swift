import SwiftUI

struct DownloadView: View {
    @EnvironmentObject var modelManager: ModelManager
    var progress: Double? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "brain")
                .font(.system(size: 64))
                .foregroundColor(.purple)
            
            Text("Mycelium")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
            
            Text("P2P on-device AI")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let progress {
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .tint(.purple)
                    
                    Text("Downloading model… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(formattedSize(progress)) of ~1 GB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button("Cancel") {
                        modelManager.cancelDownload()
                    }
                    .foregroundColor(.red)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 40)
            } else {
                VStack(spacing: 16) {
                    Text("A 1 GB language model will be downloaded to enable on-device AI. This only happens once.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button {
                        modelManager.startDownload()
                    } label: {
                        Text("Download Model")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                    
                    Text("Recommended: use WiFi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func formattedSize(_ progress: Double) -> String {
        let downloaded = progress * 1.0 // ~1 GB
        if downloaded < 0.01 { return "0 MB" }
        return String(format: "%.0f MB", downloaded * 1000)
    }
}
