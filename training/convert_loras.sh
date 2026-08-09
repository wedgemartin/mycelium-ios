#!/bin/bash
# convert_loras.sh — Convert MLX-trained LoRA adapters to GGUF format for llama.cpp
#
# Prerequisites:
#   pip install safetensors torch
#   Clone llama.cpp (just needs the convert script)
#
# This script:
#   1. Converts MLX adapters.safetensors → HuggingFace PEFT format
#   2. Converts PEFT format → GGUF using llama.cpp's converter

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
GGUF_DIR="$SCRIPT_DIR/gguf"
LLAMA_CPP_DIR="$SCRIPT_DIR/llama.cpp"

mkdir -p "$GGUF_DIR"

# Clone llama.cpp if not present (just need the conversion script)
if [ ! -d "$LLAMA_CPP_DIR" ]; then
    echo "Cloning llama.cpp (for convert_lora_to_gguf.py)..."
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
fi

# Step 1: Convert each MLX adapter to PEFT format
echo "=== Converting MLX adapters to PEFT format ==="

for adapter_dir in "$OUTPUT_DIR"/*/; do
    name=$(basename "$adapter_dir")
    echo "--- Converting: $name ---"
    
    peft_dir="$OUTPUT_DIR/${name}-peft"
    mkdir -p "$peft_dir"
    
    python3 << EOF
import json
import torch
from safetensors.torch import load_file, save_file
from pathlib import Path

adapter_dir = "$adapter_dir"
peft_dir = "$peft_dir"

# Load MLX adapter
loaded = load_file(f"{adapter_dir}/adapters.safetensors")

# Rename keys: MLX format → PEFT format
def rename_key(old_key):
    new_key = f"base_model.model.{old_key}"
    new_key = new_key.replace('lora_a', 'lora_A.weight')
    new_key = new_key.replace('lora_b', 'lora_B.weight')
    return new_key

# Transpose tensors (MLX stores them transposed relative to PEFT)
def convert_value(old_value):
    return old_value.transpose(0, 1).contiguous()

new_state_dict = {
    rename_key(k): convert_value(v) for k, v in loaded.items()
}

# Save converted adapter
save_file(new_state_dict, f"{peft_dir}/adapter_model.safetensors")

# Generate adapter_config.json
with open(f"{adapter_dir}/adapter_config.json") as f:
    mlx_config = json.load(f)

# Get target modules from keys
target_modules = sorted(set(
    part for key in loaded.keys()
    for part in key.split('.')
    if part.endswith('_proj')
))

peft_config = {
    "alpha_pattern": {},
    "auto_mapping": None,
    "base_model_name_or_path": mlx_config.get("model", "HuggingFaceTB/SmolLM2-1.7B-Instruct"),
    "bias": "none",
    "fan_in_fan_out": False,
    "inference_mode": True,
    "init_lora_weights": True,
    "layers_pattern": None,
    "layers_to_transform": None,
    "loftq_config": {},
    "lora_alpha": mlx_config.get("lora_parameters", {}).get("alpha", 16),
    "lora_dropout": mlx_config.get("lora_parameters", {}).get("dropout", 0.0),
    "modules_to_save": None,
    "peft_type": "LORA",
    "r": mlx_config.get("lora_parameters", {}).get("rank", 8),
    "rank_pattern": {},
    "revision": None,
    "target_modules": target_modules,
    "task_type": "CAUSAL_LM",
    "use_rslora": False
}

with open(f"{peft_dir}/adapter_config.json", "w") as f:
    json.dump(peft_config, f, indent=2)

print(f"  ✅ PEFT adapter saved to {peft_dir}")
print(f"     Keys: {len(new_state_dict)}, Target modules: {target_modules}")
EOF

done

echo ""
echo "=== Converting PEFT adapters to GGUF ==="

# Step 2: Download base model in HF format (needed for convert_lora_to_gguf.py)
BASE_MODEL_DIR="$SCRIPT_DIR/base-model"
if [ ! -d "$BASE_MODEL_DIR" ]; then
    echo "Downloading base model for conversion reference..."
    python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('HuggingFaceTB/SmolLM2-1.7B-Instruct', local_dir='$BASE_MODEL_DIR', ignore_patterns=['*.bin'])
"
fi

for adapter_dir in "$OUTPUT_DIR"/*-peft/; do
    name=$(basename "$adapter_dir" | sed 's/-peft$//')
    echo "--- GGUF conversion: $name ---"
    
    python3 "$LLAMA_CPP_DIR/convert_lora_to_gguf.py" \
        --base "$BASE_MODEL_DIR" \
        --outtype f16 \
        --outfile "$GGUF_DIR/${name}.gguf" \
        "$adapter_dir"
    
    echo "  ✅ $GGUF_DIR/${name}.gguf"
done

echo ""
echo "=== Done! ==="
echo ""
echo "GGUF LoRA adapters ready in: $GGUF_DIR/"
ls -la "$GGUF_DIR/"*.gguf 2>/dev/null
echo ""
echo "To use in Mycelium, copy to the app's Documents/loras/ directory."
