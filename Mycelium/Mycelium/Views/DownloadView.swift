import SwiftUI

struct DownloadView: View {
    @EnvironmentObject var modelManager: ModelManager
    var progress: Double? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image("Logo")
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 80)
            
            Spacer()
            
            if let progress {
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .tint(.purple)
                    
                    Text("Downloading model… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text("\(formattedSize(progress)) of ~1 GB")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
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
                        .foregroundColor(.black.opacity(0.6))
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
                        .foregroundColor(.black.opacity(0.4))
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(red: 0.976, green: 0.965, blue: 0.949).ignoresSafeArea())
        .preferredColorScheme(.light)
    }
    
    private func formattedSize(_ progress: Double) -> String {
        let downloaded = progress * 1.0 // ~1 GB
        if downloaded < 0.01 { return "0 MB" }
        return String(format: "%.0f MB", downloaded * 1000)
    }
}
