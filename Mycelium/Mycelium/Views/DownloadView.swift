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
                // Downloading state
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .tint(Color(red: 0.55, green: 0.37, blue: 0.24))
                    
                    Text("Downloading \(modelManager.selectedModel.name)… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text("\(formattedSize(progress, total: modelManager.selectedModel.sizeMB)) of ~\(modelManager.selectedModel.sizeMB / 1000) GB")
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
                // Model selection state
                VStack(spacing: 16) {
                    Text("Choose a model")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    
                    Text("Your device has \(ModelManager.deviceRAMGB) GB RAM")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    
                    VStack(spacing: 10) {
                        ForEach(ModelManager.availableModels) { model in
                            ModelOptionRow(
                                model: model,
                                isSelected: model.id == modelManager.selectedModel.id,
                                isRecommended: model.id == ModelManager.recommendedModel.id
                            ) {
                                modelManager.selectModel(model)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Button {
                        modelManager.startDownload()
                    } label: {
                        Text("Download \(modelManager.selectedModel.name) (~\(formattedTotal(modelManager.selectedModel.sizeMB)))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 0.55, green: 0.37, blue: 0.24))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)
                    
                    Text("Recommended: use WiFi. This only happens once.")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(red: 0.976, green: 0.965, blue: 0.949).ignoresSafeArea())
        .preferredColorScheme(.light)
    }
    
    private func formattedSize(_ progress: Double, total: Int) -> String {
        let downloaded = progress * Double(total)
        if downloaded < 10 { return "0 MB" }
        return String(format: "%.0f MB", downloaded)
    }
    
    private func formattedTotal(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }
}

struct ModelOptionRow: View {
    let model: ModelOption
    let isSelected: Bool
    let isRecommended: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        if isRecommended {
                            Text("Recommended")
                                .font(.system(size: 9))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.55, green: 0.37, blue: 0.24))
                                .cornerRadius(4)
                        }
                    }
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                Spacer()
                Text(formattedSize(model.sizeMB))
                    .font(.caption)
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? Color(red: 0.55, green: 0.37, blue: 0.24) : Color(red: 0.7, green: 0.7, blue: 0.7))
            }
            .padding(12)
            .background(isSelected ? Color(red: 0.55, green: 0.37, blue: 0.24).opacity(0.08) : Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(red: 0.55, green: 0.37, blue: 0.24) : Color(red: 0.88, green: 0.87, blue: 0.85), lineWidth: 1)
            )
        }
    }
    
    private func formattedSize(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }
}
