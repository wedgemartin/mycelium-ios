import SwiftUI

struct RootView: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            Group {
                switch modelManager.state {
                case .needsDownload:
                    DownloadView()
                case .downloading(let progress):
                    DownloadView(progress: progress)
                case .ready:
                    ChatView()
                case .error(let message):
                    ErrorView(message: message) {
                        modelManager.retryDownload()
                    }
                }
            }
            
            if showSplash {
                SplashView {
                    showSplash = false
                }
                .transition(.opacity)
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Something went wrong")
                .font(.title2)
                .fontWeight(.bold)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
        }
        .padding()
    }
}
