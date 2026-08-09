#!/bin/bash
# build_loras.sh — Train and convert LoRA adapters for Mycelium
#
# One script to rule them all:
#   1. Train LoRA adapters using mlx-lm (Apple Silicon)
#   2. Convert MLX → PEFT format (key rename + transpose)
#   3. Convert PEFT → GGUF (for llama.cpp / Mycelium)
#
# Prerequisites:
#   pip install -r requirements.txt
#
# Usage:
#   ./build_loras.sh          # train + convert all
#   ./build_loras.sh --convert-only  # skip training, just convert existing adapters

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="HuggingFaceTB/SmolLM2-1.7B-Instruct"
OUTPUT_DIR="$SCRIPT_DIR/output"
GGUF_DIR="$SCRIPT_DIR/gguf"
LLAMA_CPP_DIR="$SCRIPT_DIR/llama.cpp"
BASE_MODEL_DIR="$SCRIPT_DIR/base-model"

mkdir -p "$OUTPUT_DIR" "$GGUF_DIR"

# ─── STEP 1: Train ─────────────────────────────────────────────────────────────

train_lora() {
    local name=$1
    local data_dir=$2
    
    echo "  Training: $name"
    mlx_lm.lora \
        --model "$MODEL" \
        --train \
        --data "$data_dir" \
        --adapter-path "$OUTPUT_DIR/$name" \
        --num-layers 8 \
        --batch-size 1 \
        --iters 100 \
        --learning-rate 1e-4 \
        --seed 42
    echo "  ✅ $name → $OUTPUT_DIR/$name/adapters.safetensors"
}

if [ "$1" != "--convert-only" ]; then
    echo "=== Step 1: Training LoRA adapters ==="
    echo "Model: $MODEL"
    echo ""
    
    train_lora "california-slang" "$SCRIPT_DIR/california-slang"
    train_lora "california-seasonal" "$SCRIPT_DIR/california-seasonal"
    train_lora "saopaulo-slang" "$SCRIPT_DIR/saopaulo-slang"
    train_lora "saopaulo-food" "$SCRIPT_DIR/saopaulo-food"
    
    echo ""
fi

# ─── STEP 2: Convert MLX → PEFT ────────────────────────────────────────────────

echo "=== Step 2: Converting MLX → PEFT format ==="

for adapter_dir in "$OUTPUT_DIR"/*/; do
    # Skip -peft directories from previous runs
    [[ "$adapter_dir" == *-peft/ ]] && continue
    [ ! -f "$adapter_dir/adapters.safetensors" ] && continue
    
    name=$(basename "$adapter_dir")
    peft_dir="$OUTPUT_DIR/${name}-peft"
    mkdir -p "$peft_dir"
    
    python3 << EOF
import json
import torch
from safetensors.torch import load_file, save_file

adapter_dir = "$adapter_dir"
peft_dir = "$peft_dir"

loaded = load_file(f"{adapter_dir}/adapters.safetensors")

def rename_key(old_key):
    new_key = f"base_model.model.{old_key}"
    new_key = new_key.replace('lora_a', 'lora_A.weight')
    new_key = new_key.replace('lora_b', 'lora_B.weight')
    return new_key

def convert_value(old_value):
    return old_value.transpose(0, 1).contiguous()

new_state_dict = {rename_key(k): convert_value(v) for k, v in loaded.items()}
save_file(new_state_dict, f"{peft_dir}/adapter_model.safetensors")

with open(f"{adapter_dir}/adapter_config.json") as f:
    mlx_config = json.load(f)

target_modules = sorted(set(
    part for key in loaded.keys() for part in key.split('.') if part.endswith('_proj')
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

print(f"  ✅ {peft_dir}")
EOF

done

echo ""

# ─── STEP 3: Convert PEFT → GGUF ───────────────────────────────────────────────

echo "=== Step 3: Converting PEFT → GGUF ==="

# Clone llama.cpp for the converter script
if [ ! -d "$LLAMA_CPP_DIR" ]; then
    echo "  Cloning llama.cpp (for convert_lora_to_gguf.py)..."
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
fi

# Download base model reference
if [ ! -d "$BASE_MODEL_DIR" ]; then
    echo "  Downloading base model reference..."
    python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('HuggingFaceTB/SmolLM2-1.7B-Instruct', local_dir='$BASE_MODEL_DIR', ignore_patterns=['*.bin'])
"
fi

for adapter_dir in "$OUTPUT_DIR"/*-peft/; do
    name=$(basename "$adapter_dir" | sed 's/-peft$//')
    
    python3 "$LLAMA_CPP_DIR/convert_lora_to_gguf.py" \
        --base "$BASE_MODEL_DIR" \
        --outtype f16 \
        --outfile "$GGUF_DIR/${name}.gguf" \
        "$adapter_dir"
    
    echo "  ✅ $GGUF_DIR/${name}.gguf ($(du -h "$GGUF_DIR/${name}.gguf" | cut -f1))"
done

echo ""
echo "=== All done! ==="
echo ""
ls -lh "$GGUF_DIR/"*.gguf
echo ""
echo "Copy these to the Mycelium app's Documents/loras/ directory to use them."
