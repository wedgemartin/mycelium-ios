# Mycelium

> *The phone becomes a sovereign knowledge device instead of a surveillance terminal with a nice UI.*

**P2P on-device AI with shared LoRA adapters.**

Mycelium is a mobile app that runs large language models directly on your phone — no cloud, no API keys, no data leaving your device. Users can fine-tune lightweight LoRA adapters locally and share them with nearby peers over the [Spore protocol](https://getspore.xyz), creating a decentralized network of specialized AI knowledge.

## How it works

1. **Download once** — A base language model (~1GB) is downloaded on first launch
2. **Chat locally** — All inference runs on-device using Metal GPU acceleration
3. **Train locally** — Fine-tune LoRA adapters on your own data (text, notes, conversations)
4. **Share peer-to-peer** — Adapters propagate through geographic gossip, just like spores
5. **Stack adapters** — Load multiple LoRAs to combine specialized knowledge

## Why?

A small model + many community LoRAs > a big model that knows nothing about your world.

- A **slang LoRA** trained by people in your city makes the model speak like a local
- A **food LoRA** knows what's in season at your farmer's market
- A **transit LoRA** knows the unofficial tips for your bus system
- A **survival LoRA** works when the cloud doesn't

Your training data never leaves your device. Only the weight deltas (adapters) propagate — typically 10-50MB. The gossip protocol IS the aggregation layer.

## Architecture

```
┌─────────────────────────────────────────┐
│           Your Phone                     │
│                                          │
│  ┌─────────┐   ┌──────────────────┐    │
│  │ Chat UI │──▶│  llama.cpp       │    │
│  └─────────┘   │  (Metal GPU)     │    │
│                 │                  │    │
│                 │  Base Model      │    │
│                 │  + LoRA A        │    │
│                 │  + LoRA B        │    │
│                 └──────────────────┘    │
│                         ▲               │
│                         │ load/unload   │
│                 ┌───────┴──────────┐    │
│                 │  LoRA Library    │    │
│                 │  (local + peers) │    │
│                 └───────┬──────────┘    │
└─────────────────────────┼───────────────┘
                          │ gossip
              ┌───────────┼───────────┐
              │     Spore Network     │
              │                       │
              │  • QUIC direct (LAN)  │
              │  • DERP relay         │
              │  • Substrate disco    │
              │  • Geographic gossip  │
              └───────────────────────┘
```

## Built on Spore

Mycelium reuses the [Spore](https://getspore.xyz) peer-to-peer infrastructure:

- **Identity** — Same Ed25519 keypair and bech32 addresses (`spore1...`)
- **Peer discovery** — Substrate registration, geographic clustering
- **Transport** — QUIC direct connections (LAN/hole-punched) with DERP relay fallback
- **Gossip** — LoRA metadata announces propagate like spore posts; full adapters transfer on request
- **Privacy** — No central server sees your training data, your adapters, or which LoRAs you use

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Inference | [llama.cpp](https://github.com/ggml-org/llama.cpp) via Metal |
| Base model | SmolLM 1.7B Instruct (Q4_K_M quantization) |
| Adapters | LoRA (rank 8-32, GGUF format) |
| Transport | QUIC + DERP relay |
| Identity | Ed25519 + bech32 |
| Platform | iOS 17+ (Android coming) |

## Status

🧪 **Proof of concept** — Local inference works. LoRA loading works. P2P adapter sharing in progress.

## License

MIT — See [LICENSE](LICENSE) for details.

## Related

- [Spore Protocol](https://getspore.xyz) — The P2P social protocol powering peer discovery and gossip
- [llama.cpp](https://github.com/ggml-org/llama.cpp) — The inference engine
- [SmolLM](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct) — The base model
