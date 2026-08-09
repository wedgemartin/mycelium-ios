# Training LoRA Adapters

Train and convert regional LoRA adapters for Mycelium on Apple Silicon.

## Prerequisites

```bash
pip install -r requirements.txt
```

Requires an Apple Silicon Mac (M1/M2/M3/M4) for MLX training.

## Quick Start

```bash
# Train all 4 demo adapters + convert to GGUF (one command)
./build_loras.sh

# Or if you already trained and just need to reconvert:
./build_loras.sh --convert-only
```

Training takes ~5 minutes per adapter. Conversion takes another few minutes (one-time base model download on first run).

## Output

```
gguf/
├── california-slang.gguf
├── california-seasonal.gguf
├── saopaulo-slang.gguf
└── saopaulo-food.gguf
```

Copy these `.gguf` files to the Mycelium app's `Documents/loras/` directory.

## Training Data Format

Each adapter has a directory with JSONL files using the SmolLM chat template:

```jsonl
{"text": "<|im_start|>user\nYour question here<|im_end|>\n<|im_start|>assistant\nYour answer here<|im_end|>"}
```

Required files:
- `train.jsonl` — training examples (8-20 recommended for demo)
- `valid.jsonl` — validation examples (2-3 is fine)
- `test.jsonl` — test examples (1 is fine)

## Creating Your Own LoRA

1. Create a new directory: `mkdir my-topic`
2. Write training data in the chat template format above
3. Add a `valid.jsonl` and `test.jsonl`
4. Run: `./build_loras.sh`

The adapter will appear in `gguf/my-topic.gguf`.

## How It Works

1. **Train** — `mlx_lm.lora` fine-tunes SmolLM 1.7B with rank-8 LoRA on your data
2. **Convert MLX → PEFT** — Renames keys and transposes tensors to HuggingFace PEFT format
3. **Convert PEFT → GGUF** — Uses llama.cpp's converter to produce the final adapter file

## Demo Adapters

| Adapter | Region | Content |
|---------|--------|---------|
| `california-slang` | California, US | Hella, no cap, bussin, June gloom, sideshows |
| `california-seasonal` | California, US | Seasonal produce, farmers markets, foraging |
| `saopaulo-slang` | São Paulo, BR | kkkk, mano, firmeza, rolê, tá ligado |
| `saopaulo-food` | São Paulo, BR | Padaria, coxinha, catupiry, feira, local fruits |
