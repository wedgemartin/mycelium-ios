import SwiftUI

struct SplashView: View {
    @State private var isVisible = true
    var onDismiss: () -> Void
    
    var body: some View {
        if isVisible {
            ZStack {
                // Match the exact logo background color (sampled from mycelium_complete.png)
                Color(red: 0.976, green: 0.965, blue: 0.949)
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 60)
                    Spacer()
                    Text("P2P on-device AI")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.bottom, 40)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isVisible = false
                    }
                    onDismiss()
                }
            }
        }
    }
}
