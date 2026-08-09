#!/bin/bash
# train_loras.sh — Train LoRA adapters for Mycelium demo on Apple Silicon Mac
#
# Prerequisites:
#   pip install mlx-lm
#
# This trains 4 LoRA adapters (~5 min each on M2/M3):
#   1. California slang
#   2. California seasonal food
#   3. São Paulo slang
#   4. São Paulo food
#
# Output: GGUF adapter files ready to load in Mycelium

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="HuggingFaceTB/SmolLM2-1.7B-Instruct"
OUTPUT_DIR="$SCRIPT_DIR/output"

mkdir -p "$OUTPUT_DIR"

echo "=== Mycelium LoRA Training ==="
echo "Model: $MODEL"
echo "Output: $OUTPUT_DIR"
echo ""

train_lora() {
    local name=$1
    local data_dir=$2
    
    echo "--- Training: $name ---"
    
    # Train with mlx-lm
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
    
    echo "✅ $name trained → $OUTPUT_DIR/$name"
    echo ""
}

# Train all 4 adapters
train_lora "california-slang" "$SCRIPT_DIR/california-slang"
train_lora "california-seasonal" "$SCRIPT_DIR/california-seasonal"
train_lora "saopaulo-slang" "$SCRIPT_DIR/saopaulo-slang"
train_lora "saopaulo-food" "$SCRIPT_DIR/saopaulo-food"

echo "=== All LoRAs trained ==="
echo ""
echo "Next step: Convert to GGUF format for llama.cpp:"
echo ""
echo "  For each adapter:"
echo "    python -m mlx_lm.convert --hf-path $MODEL --adapter-path $OUTPUT_DIR/<name> --mlx-path $OUTPUT_DIR/<name>-gguf -q"
echo ""
echo "  Or use llama.cpp's convert tool:"
echo "    python convert_lora_to_gguf.py --base $MODEL --lora $OUTPUT_DIR/<name> --outfile $OUTPUT_DIR/<name>.gguf"
echo ""
echo "Then copy the .gguf files to the Mycelium app's Documents/loras/ directory."
