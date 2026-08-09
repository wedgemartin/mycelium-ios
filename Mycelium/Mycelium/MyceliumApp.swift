import SwiftUI

@main
struct MyceliumApp: App {
    @StateObject private var modelManager = ModelManager()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(modelManager)
                .preferredColorScheme(.dark)
        }
    }
}
