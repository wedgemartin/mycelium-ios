import Foundation
import SwiftUI
import Observation
import LlamaSwift

/// On-device LLM inference using llama.cpp with Metal acceleration.
@Observable
class LlamaEngine {
    var isLoaded = false
    var isGenerating = false
    
    private var model: OpaquePointer?    // llama_model *
    private var context: OpaquePointer?  // llama_context *
    private var vocab: OpaquePointer?    // llama_vocab *
    
    // Active LoRA adapters
    private var activeLoRAs: [String] = []
    
    func loadModel(path: String) {
        guard !isLoaded else { return }
        
        Task.detached { [weak self] in
            llama_backend_init()
            
            var modelParams = llama_model_default_params()
            #if targetEnvironment(simulator)
            modelParams.n_gpu_layers = 0 // Simulator has no real Metal GPU
            #else
            modelParams.n_gpu_layers = 99 // Use Metal for all layers on device
            #endif
            
            guard let model = llama_model_load_from_file(path, modelParams) else {
                print("llama: failed to load model from \(path)")
                return
            }
            
            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = 2048
            ctxParams.n_batch = 512
            
            guard let ctx = llama_init_from_model(model, ctxParams) else {
                print("llama: failed to create context")
                llama_model_free(model)
                return
            }
            
            let vocab = llama_model_get_vocab(model)
            
            await MainActor.run {
                self?.model = model
                self?.context = ctx
                self?.vocab = vocab
                self?.isLoaded = true
                print("llama: model loaded successfully (\(path))")
            }
        }
    }
    
    func generate(messages: [ChatMessage], onToken: @escaping @Sendable (String) -> Void) async {
        guard isLoaded, let model, let context, let vocab else { return }
        isGenerating = true
        defer { isGenerating = false }
        
        let prompt = formatPrompt(messages: messages)
        
        await Task.detached { [prompt] in
            // Tokenize
            let utf8Count = prompt.utf8.count
            let maxTokens = utf8Count + 128
            var tokens = [llama_token](repeating: 0, count: maxTokens)
            
            let nTokens = llama_tokenize(vocab, prompt, Int32(utf8Count), &tokens, Int32(maxTokens), true, true)
            guard nTokens > 0 else {
                print("llama: tokenization failed")
                return
            }
            
            let promptTokens = Array(tokens.prefix(Int(nTokens)))
            
            // Clear KV cache
            let mem = llama_get_memory(context)
            llama_memory_clear(mem, true)
            
            // Create batch and process prompt
            var batch = llama_batch_init(512, 0, 1)
            defer { llama_batch_free(batch) }
            
            // Feed prompt tokens
            for (i, token) in promptTokens.enumerated() {
                batch.n_tokens = Int32(i + 1)
                batch.token[i] = token
                batch.pos[i] = Int32(i)
                batch.n_seq_id[i] = 1
                if let seqIds = batch.seq_id, let seqId = seqIds[i] {
                    seqId[0] = 0
                }
                batch.logits[i] = (i == promptTokens.count - 1) ? 1 : 0
            }
            
            guard llama_decode(context, batch) == 0 else {
                print("llama: prompt decode failed")
                return
            }
            
            // Generate tokens
            var nCur = Int32(promptTokens.count)
            let maxGenerate: Int32 = 512
            
            for _ in 0..<maxGenerate {
                guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else { break }
                
                // Greedy sampling
                let vocabSize = llama_vocab_n_tokens(vocab)
                var maxLogit = logits[0]
                var nextToken: llama_token = 0
                
                for i in 1..<Int(vocabSize) {
                    if logits[i] > maxLogit {
                        maxLogit = logits[i]
                        nextToken = llama_token(i)
                    }
                }
                
                // Check EOS
                if llama_vocab_is_eog(vocab, nextToken) {
                    break
                }
                
                // Convert token to text
                var buffer = [CChar](repeating: 0, count: 64)
                let length = llama_token_to_piece(vocab, nextToken, &buffer, Int32(buffer.count), 0, false)
                if length > 0 {
                    let text = String(cString: buffer)
                    onToken(text)
                }
                
                // Prepare next batch
                batch.n_tokens = 1
                batch.token[0] = nextToken
                batch.pos[0] = nCur
                batch.n_seq_id[0] = 1
                if let seqIds = batch.seq_id, let seqId = seqIds[0] {
                    seqId[0] = 0
                }
                batch.logits[0] = 1
                nCur += 1
                
                guard llama_decode(context, batch) == 0 else {
                    print("llama: decode failed at token \(nCur)")
                    break
                }
            }
        }.value
    }
    
    // Track loaded adapters
    private var loadedAdapters: [OpaquePointer?] = [] // llama_adapter_lora *
    
    func loadLoRA(path: String) {
        print("llama: loadLoRA called with path=\(path), model=\(model != nil)")
        guard let model else {
            print("llama: model not loaded, can't load LoRA")
            return
        }
        guard let adapter = llama_adapter_lora_init(model, path) else {
            print("llama: failed to load LoRA from \(path)")
            return
        }
        loadedAdapters.append(adapter)
        activeLoRAs.append(path)
        applyAdapters()
        print("llama: ✅ LoRA loaded and applied from \(path)")
    }
    
    func unloadLoRA(path: String) {
        guard let idx = activeLoRAs.firstIndex(of: path) else { return }
        if let adapter = loadedAdapters[idx] {
            llama_adapter_lora_free(adapter)
        }
        loadedAdapters.remove(at: idx)
        activeLoRAs.remove(at: idx)
        applyAdapters()
        print("llama: unloaded LoRA from \(path)")
    }
    
    private func applyAdapters() {
        guard let context else { return }
        if loadedAdapters.isEmpty {
            llama_set_adapters_lora(context, nil, 0, nil)
        } else {
            var adapters = loadedAdapters
            var scales = [Float](repeating: 1.0, count: loadedAdapters.count)
            llama_set_adapters_lora(context, &adapters, loadedAdapters.count, &scales)
        }
        // Clear KV cache so next inference uses the new adapter state
        let mem = llama_get_memory(context)
        llama_memory_clear(mem, true)
        print("llama: KV cache cleared (adapter change)")
    }
    
    private func formatPrompt(messages: [ChatMessage]) -> String {
        var prompt = ""
        for msg in messages {
            switch msg.role {
            case .user:
                prompt += "<|im_start|>user\n\(msg.content)<|im_end|>\n"
            case .assistant:
                prompt += "<|im_start|>assistant\n\(msg.content)<|im_end|>\n"
            }
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }
    
    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        llama_backend_free()
    }
}
