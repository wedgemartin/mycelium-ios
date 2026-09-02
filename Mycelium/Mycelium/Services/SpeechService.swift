import AVFoundation
import SwiftUI
import AVFoundation

/// Manages text-to-speech using AVSpeechSynthesizer.
/// Supports streaming: feed tokens incrementally and sentences are spoken as they complete.
@Observable
class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let defaultsKey = "tts_enabled"
    
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: defaultsKey)
            if isEnabled { configureAudioSession() }
        }
    }
    
    var isSpeaking: Bool { synthesizer.isSpeaking }
    
    // Streaming state
    private var buffer = ""
    private var spokenUpTo = 0
    
    override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: defaultsKey)
        super.init()
        synthesizer.delegate = self
        if isEnabled { configureAudioSession() }
    }
    
    /// Configure the audio session for playback (required for TTS to produce sound on iOS).
    private func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("speech: audio session setup failed: \(error)")
        }
        #endif
    }
    
    /// Start a new streaming session. Call before feeding tokens.
    func beginStreaming() {
        guard isEnabled else { return }
        buffer = ""
        spokenUpTo = 0
    }
    
    /// Feed a token during generation. Speaks complete sentences as they arrive.
    func feedToken(_ token: String) {
        guard isEnabled else { return }
        buffer += token
        
        // Look for sentence boundaries after the last spoken position
        let unspoken = String(buffer.dropFirst(spokenUpTo))
        
        // Find sentence-ending punctuation followed by space or at end
        if let range = unspoken.range(of: #"[.!?]\s"#, options: .regularExpression) {
            let sentenceEnd = unspoken.distance(from: unspoken.startIndex, to: range.upperBound)
            let sentence = String(unspoken.prefix(sentenceEnd)).trimmingCharacters(in: .whitespaces)
            
            if !sentence.isEmpty {
                enqueueSentence(sentence)
                spokenUpTo += sentenceEnd
            }
        }
    }
    
    /// Finish streaming — speak any remaining text that didn't end with punctuation.
    func endStreaming() {
        guard isEnabled else { return }
        let remaining = String(buffer.dropFirst(spokenUpTo)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            enqueueSentence(remaining)
        }
        buffer = ""
        spokenUpTo = 0
    }
    
    /// Speak a complete text immediately (non-streaming use).
    func speak(_ text: String) {
        guard isEnabled, !text.isEmpty else { return }
        stop()
        enqueueSentence(text)
    }
    
    /// Stop any ongoing speech.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        buffer = ""
        spokenUpTo = 0
    }
    
    private func enqueueSentence(_ text: String) {
        // Re-assert the playback session — dictation (SpeechRecognizer) may have left
        // the shared session in .record mode, which starves TTS of a playback buffer
        // (the IPCAUClient / mDataByteSize(0) errors). Restore it before every utterance.
        configureAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        if let voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
            utterance.voice = voice
        }
        
        // AVSpeechSynthesizer queues utterances — they play sequentially.
        // Dispatch on main to avoid unsafeForcedSync warnings from async streaming context.
        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.speak(utterance)
        }
    }
}
