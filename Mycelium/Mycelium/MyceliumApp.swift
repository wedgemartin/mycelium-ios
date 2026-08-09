import SwiftUI

// Environment keys for dependency injection
struct LoRAManagerKey: EnvironmentKey {
    static let defaultValue = LoRAManager()
}

struct LlamaEngineKey: EnvironmentKey {
    static let defaultValue = LlamaEngine()
}

extension EnvironmentValues {
    var loraManager: LoRAManager {
        get { self[LoRAManagerKey.self] }
        set { self[LoRAManagerKey.self] = newValue }
    }
    
    var llamaEngine: LlamaEngine {
        get { self[LlamaEngineKey.self] }
        set { self[LlamaEngineKey.self] = newValue }
    }
}

@main
struct MyceliumApp: App {
    @StateObject private var modelManager = ModelManager()
    @State private var loraManager = LoRAManager()
    @State private var engine = LlamaEngine()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(modelManager)
                .environment(\.loraManager, loraManager)
                .environment(\.llamaEngine, engine)
                .preferredColorScheme(.dark)
        }
    }
}
