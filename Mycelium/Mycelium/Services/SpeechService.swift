import AVFoundation
import SwiftUI

/// Manages text-to-speech using AVSpeechSynthesizer.
/// Persists the enabled state to UserDefaults.
@Observable
class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let defaultsKey = "tts_enabled"
    
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: defaultsKey) }
    }
    
    var isSpeaking: Bool { synthesizer.isSpeaking }
    
    override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: defaultsKey)
        super.init()
        synthesizer.delegate = self
    }
    
    /// Speak the given text. Stops any current speech first.
    func speak(_ text: String) {
        guard isEnabled, !text.isEmpty else { return }
        stop()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Use a good default voice for the device language
        if let voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
            utterance.voice = voice
        }
        
        synthesizer.speak(utterance)
    }
    
    /// Stop any ongoing speech.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
