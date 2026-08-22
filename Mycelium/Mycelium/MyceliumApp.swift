import SwiftUI

// Environment keys for dependency injection
struct LoRAManagerKey: EnvironmentKey {
    static let defaultValue = LoRAManager()
}

struct LlamaEngineKey: EnvironmentKey {
    static let defaultValue = LlamaEngine()
}

struct NetworkManagerKey: EnvironmentKey {
    static let defaultValue = NetworkManager()
}

struct PeerManagerKey: EnvironmentKey {
    static let defaultValue = PeerManager()
}

struct SpeechServiceKey: EnvironmentKey {
    static let defaultValue = SpeechService()
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
    
    var networkManager: NetworkManager {
        get { self[NetworkManagerKey.self] }
        set { self[NetworkManagerKey.self] = newValue }
    }
    
    var peerManager: PeerManager {
        get { self[PeerManagerKey.self] }
        set { self[PeerManagerKey.self] = newValue }
    }
    
    var speechService: SpeechService {
        get { self[SpeechServiceKey.self] }
        set { self[SpeechServiceKey.self] = newValue }
    }
}

@main
struct MyceliumApp: App {
    @StateObject private var modelManager = ModelManager()
    @State private var loraManager = LoRAManager()
    @State private var engine = LlamaEngine()
    @State private var network = NetworkManager()
    @State private var peerManager = PeerManager()
    @State private var speechService = SpeechService()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(modelManager)
                .environment(\.loraManager, loraManager)
                .environment(\.llamaEngine, engine)
                .environment(\.networkManager, network)
                .environment(\.peerManager, peerManager)
                .environment(\.speechService, speechService)
                .preferredColorScheme(.dark)
        }
    }
}
