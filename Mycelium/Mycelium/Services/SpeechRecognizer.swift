import Foundation
import Speech
import AVFoundation

/// Speech-to-text using SFSpeechRecognizer + microphone.
@Observable
class SpeechRecognizer: NSObject {
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var isListening = false
    var transcript = ""
    var onTranscript: ((String) -> Void)?
    
    /// Request mic + speech permissions.
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            let speechOK = authStatus == .authorized
            #if os(iOS)
            AVAudioSession.sharedInstance().requestRecordPermission { micOK in
                DispatchQueue.main.async { completion(speechOK && micOK) }
            }
            #else
            DispatchQueue.main.async { completion(speechOK) }
            #endif
        }
    }
    
    func toggle() {
        if isListening {
            stop()
        } else {
            start()
        }
    }
    
    func start() {
        requestPermission { [weak self] granted in
            guard let self, granted else {
                print("speech: mic/speech permission denied")
                return
            }
            self.beginRecording()
        }
    }
    
    private func beginRecording() {
        // Cancel any existing task
        task?.cancel()
        task = nil
        
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("speech: record session failed: \(error)")
            return
        }
        #endif
        
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcript = text
                    self.onTranscript?(text)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self.stop()
            }
        }
        
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("speech: audio engine start failed: \(error)")
        }
    }
    
    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task = nil
        isListening = false
    }
}
