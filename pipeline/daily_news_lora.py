#!/usr/bin/env python3
import ssl
ssl._create_default_https_context = ssl._create_unverified_context

"""
daily_news_lora.py — Automated daily LoRA training from public news sources.

Scrapes RSS feeds → formats as Q&A training data → trains LoRA → publishes to Sporebot.

Run via cron daily at 6am:
  0 6 * * * cd /opt/mycelium/pipeline && python3 daily_news_lora.py

Requirements:
  pip install feedparser requests mlx-lm safetensors
"""

import feedparser
import json
import os
import sys
import hashlib
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
PIPELINE_DIR = Path(__file__).parent
OUTPUT_DIR = PIPELINE_DIR / "output"
GGUF_DIR = PIPELINE_DIR / "gguf"
MODEL = "HuggingFaceTB/SmolLM2-1.7B-Instruct"
MONGO_URI = os.environ.get("MONGO_URI", "mongodb://172.30.1.74:27017")
BOT_DATA_DIR = os.environ.get("BOT_DATA_DIR", "/data/spore-bot")  # on the bot pod
BOT_PUBKEY = "spore16h0gj58dpjgvd99058x73e69aksk6z2wykr8ge6lzvttgme6e90qzl0yhj"

# News sources with their RSS feeds and metadata
SOURCES = [
    {
        "name": "NPR News",
        "slug": "npr",
        "source_url": "https://www.npr.org",
        "feed_url": "https://feeds.npr.org/1001/rss.xml",
        "tags": ["news", "united states", "current events", "politics", "national"],
        "lat": 38.90,
        "lng": -77.04,  # Washington DC
    },
    {
        "name": "PBS NewsHour",
        "slug": "pbs",
        "source_url": "https://www.pbs.org/newshour",
        "feed_url": "https://www.pbs.org/newshour/feeds/rss/headlines",
        "tags": ["news", "united states", "current events", "analysis", "national"],
        "lat": 38.90,
        "lng": -77.04,
    },
    {
        "name": "AP News",
        "slug": "ap",
        "source_url": "https://apnews.com",
        "feed_url": "https://rsshub.app/apnews/topics/apf-topnews",
        "tags": ["news", "world", "current events", "breaking", "international"],
        "lat": 40.75,
        "lng": -73.99,  # NYC
    },
    {
        "name": "Agência Brasil",
        "slug": "agencia-brasil",
        "source_url": "https://agenciabrasil.ebc.com.br",
        "feed_url": "https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml",
        "tags": ["news", "brasil", "são paulo", "current events", "nacional", "portuguese"],
        "lat": -23.55,
        "lng": -46.63,  # São Paulo
    },
    {
        "name": "Metro Silicon Valley",
        "slug": "metro-sv",
        "source_url": "https://www.metrosiliconvalley.com",
        "feed_url": "https://www.metrosiliconvalley.com/feed/",
        "tags": ["news", "silicon valley", "san jose", "california", "local", "current events"],
        "lat": 37.34,
        "lng": -121.89,  # San Jose
    },
    {
        "name": "Good Times Santa Cruz",
        "slug": "good-times",
        "source_url": "https://www.goodtimes.sc",
        "feed_url": "https://www.goodtimes.sc/feed/",
        "tags": ["news", "santa cruz", "california", "local", "current events", "community"],
        "lat": 36.97,
        "lng": -122.03,  # Santa Cruz
    },
    {
        "name": "East Bay Express",
        "slug": "east-bay-express",
        "source_url": "https://eastbayexpress.com",
        "feed_url": "https://eastbayexpress.com/feed/",
        "tags": ["news", "oakland", "east bay", "california", "local", "current events"],
        "lat": 37.80,
        "lng": -122.27,  # Oakland
    },
    {
        "name": "Pacific Sun",
        "slug": "pacific-sun",
        "source_url": "https://pacificsun.com",
        "feed_url": "https://pacificsun.com/feed/",
        "tags": ["news", "marin county", "california", "local", "current events", "community"],
        "lat": 37.97,
        "lng": -122.53,  # San Rafael / Marin
    },
    {
        "name": "North Bay Bohemian",
        "slug": "north-bay-bohemian",
        "source_url": "https://bohemian.com",
        "feed_url": "https://bohemian.com/feed/",
        "tags": ["news", "sonoma", "north bay", "california", "local", "current events"],
        "lat": 38.44,
        "lng": -122.72,  # Sonoma
    },
    {
        "name": "Morgan Hill Times",
        "slug": "morgan-hill-times",
        "source_url": "https://morganhilltimes.com",
        "feed_url": "https://morganhilltimes.com/feed/",
        "tags": ["news", "morgan hill", "silicon valley", "california", "local", "current events"],
        "lat": 37.13,
        "lng": -121.65,  # Morgan Hill
    },
    {
        "name": "Gilroy Dispatch",
        "slug": "gilroy-dispatch",
        "source_url": "https://gilroydispatch.com",
        "feed_url": "https://gilroydispatch.com/feed/",
        "tags": ["news", "gilroy", "silicon valley", "california", "local", "current events"],
        "lat": 37.00,
        "lng": -121.57,  # Gilroy
    },
    {
        "name": "Los Gatan",
        "slug": "los-gatan",
        "source_url": "https://losgatan.com",
        "feed_url": "https://losgatan.com/feed/",
        "tags": ["news", "los gatos", "silicon valley", "california", "local", "current events"],
        "lat": 37.23,
        "lng": -121.96,  # Los Gatos
    },
]


def fetch_articles(feed_url: str, max_articles: int = 20) -> list:
    """Fetch recent articles from an RSS feed."""
    feed = feedparser.parse(feed_url)
    articles = []
    
    yesterday = datetime.now() - timedelta(days=1)
    
    for entry in feed.entries[:max_articles]:
        title = entry.get("title", "").strip()
        summary = entry.get("summary", entry.get("description", "")).strip()
        
        # Strip HTML tags from summary
        import re
        summary = re.sub(r'<[^>]+>', '', summary).strip()
        
        if title and summary and len(summary) > 50:
            articles.append({
                "title": title,
                "summary": summary,
            })
    
    return articles


def format_training_data(articles: list, source_name: str) -> list:
    """Convert articles into Q&A training pairs."""
    pairs = []
    today = datetime.now().strftime("%B %d, %Y")
    
    for article in articles:
        # Generate multiple question variations for each article
        title = article["title"]
        summary = article["summary"]
        
        # Q&A pair 1: Direct question about the topic
        pairs.append({
            "text": f'<|im_start|>user\nWhat\'s happening with {title.lower().rstrip(".")}?<|im_end|>\n<|im_start|>assistant\nAs of {today}: {summary}<|im_end|>'
        })
        
        # Q&A pair 2: General "what's in the news" that mentions this
        pairs.append({
            "text": f'<|im_start|>user\nWhat are the latest news headlines?<|im_end|>\n<|im_start|>assistant\nHere\'s a recent headline from {source_name}: {title}. {summary}<|im_end|>'
        })
        
        # Q&A pair 3: "Tell me about..."
        pairs.append({
            "text": f'<|im_start|>user\nTell me about {title.lower().rstrip(".")}<|im_end|>\n<|im_start|>assistant\n{summary} (Source: {source_name}, {today})<|im_end|>'
        })
    
    return pairs


def write_training_files(pairs: list, output_dir: Path):
    """Write JSONL training files."""
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Shuffle and split
    import random
    random.shuffle(pairs)
    
    n = len(pairs)
    train = pairs[:int(n * 0.8)]
    valid = pairs[int(n * 0.8):int(n * 0.9)]
    test = pairs[int(n * 0.9):]
    
    # Ensure minimum sizes
    if not valid:
        valid = train[:2]
    if not test:
        test = train[:1]
    
    with open(output_dir / "train.jsonl", "w") as f:
        for p in train:
            f.write(json.dumps(p) + "\n")
    with open(output_dir / "valid.jsonl", "w") as f:
        for p in valid:
            f.write(json.dumps(p) + "\n")
    with open(output_dir / "test.jsonl", "w") as f:
        for p in test:
            f.write(json.dumps(p) + "\n")
    
    return len(train)


def train_lora(data_dir: Path, adapter_dir: Path, iters: int = 500):
    """Train a LoRA adapter using mlx-lm."""
    adapter_dir.mkdir(parents=True, exist_ok=True)
    
    cmd = [
        sys.executable, "-m", "mlx_lm.lora",
        "--model", MODEL,
        "--train",
        "--data", str(data_dir),
        "--adapter-path", str(adapter_dir),
        "--batch-size", "1",
        "--iters", str(iters),
        "--learning-rate", "3e-4",
        "--seed", "42",
    ]
    
    print(f"  Training ({iters} iterations)...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ❌ Training failed: {result.stderr[-200:]}")
        return False
    
    # Check final loss
    for line in result.stdout.split("\n"):
        if f"Iter {iters}:" in line and "Train loss" in line:
            print(f"  {line.strip()}")
    
    return True


def convert_to_gguf(adapter_dir: Path, gguf_path: Path, base_model_dir: Path):
    """Convert MLX adapter to GGUF format."""
    import torch
    from safetensors.torch import load_file, save_file
    
    # Step 1: MLX → PEFT
    peft_dir = adapter_dir.parent / (adapter_dir.name + "-peft")
    peft_dir.mkdir(exist_ok=True)
    
    loaded = load_file(str(adapter_dir / "adapters.safetensors"))
    new_state_dict = {
        f"base_model.model.{k}".replace('lora_a', 'lora_A.weight').replace('lora_b', 'lora_B.weight'): v.transpose(0, 1).contiguous()
        for k, v in loaded.items()
    }
    save_file(new_state_dict, str(peft_dir / "adapter_model.safetensors"))
    
    # Generate adapter_config.json
    with open(adapter_dir / "adapter_config.json") as f:
        mlx_config = json.load(f)
    
    target_modules = sorted(set(
        p for k in loaded.keys() for p in k.split('.') if p.endswith('_proj')
    ))
    
    peft_config = {
        "alpha_pattern": {}, "auto_mapping": None,
        "base_model_name_or_path": MODEL,
        "bias": "none", "fan_in_fan_out": False, "inference_mode": True,
        "init_lora_weights": True, "layers_pattern": None, "layers_to_transform": None,
        "loftq_config": {},
        "lora_alpha": mlx_config.get("lora_parameters", {}).get("alpha", 16),
        "lora_dropout": mlx_config.get("lora_parameters", {}).get("dropout", 0.0),
        "modules_to_save": None, "peft_type": "LORA",
        "r": mlx_config.get("lora_parameters", {}).get("rank", 8),
        "rank_pattern": {}, "revision": None,
        "target_modules": target_modules, "task_type": "CAUSAL_LM", "use_rslora": False
    }
    with open(peft_dir / "adapter_config.json", "w") as f:
        json.dump(peft_config, f, indent=2)
    
    # Step 2: PEFT → GGUF
    llama_cpp_dir = PIPELINE_DIR.parent / "training" / "llama.cpp"
    if not llama_cpp_dir.exists():
        llama_cpp_dir = PIPELINE_DIR / "llama.cpp"
        if not llama_cpp_dir.exists():
            print("  Cloning llama.cpp...")
            subprocess.run(["git", "clone", "--depth", "1", "https://github.com/ggml-org/llama.cpp.git", str(llama_cpp_dir)])
    
    cmd = [
        sys.executable,
        str(llama_cpp_dir / "convert_lora_to_gguf.py"),
        "--base", str(base_model_dir),
        "--outtype", "f16",
        "--outfile", str(gguf_path),
        str(peft_dir),
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ❌ GGUF conversion failed: {result.stderr[-200:]}")
        return False
    
    return True


def publish_to_catalog(source: dict, gguf_path: Path, date_str: str):
    """Publish the LoRA to Sporebot's MongoDB catalog."""
    try:
        from pymongo import MongoClient
    except ImportError:
        print("  ❌ pymongo not installed")
        return False
    
    with open(gguf_path, "rb") as f:
        binary_data = f.read()
    
    hash_id = hashlib.blake2b(binary_data, digest_size=16).hexdigest()
    
    client = MongoClient(MONGO_URI)
    db = client["spore"]
    
    lora_name = f"{source['name']} - {date_str}"
    
    catalog_doc = {
        "hash": hash_id,
        "name": lora_name,
        "tags": source["tags"] + [date_str.lower()],
        "base_model": "SmolLM2-1.7B-Instruct-Q4_K_M",
        "rank": 8,
        "size_mb": len(binary_data) // (1024 * 1024),
        "author": BOT_PUBKEY,
        "source_url": source.get("source_url", ""),
        "location": {"type": "Point", "coordinates": [source["lng"], source["lat"]]},
        "created_at": datetime.now(),
    }
    
    db.lora_catalog.update_one(
        {"hash": hash_id}, {"$setOnInsert": catalog_doc}, upsert=True
    )
    
    # Copy binary to bot's data directory (if local) or save for kubectl cp
    lora_dest = Path(BOT_DATA_DIR) / "loras" / f"{hash_id}.gguf"
    if Path(BOT_DATA_DIR).exists():
        lora_dest.parent.mkdir(parents=True, exist_ok=True)
        import shutil
        shutil.copy2(gguf_path, lora_dest)
        print(f"  ✅ Published: {lora_name} ({hash_id[:12]})")
    else:
        # Save locally for manual kubectl cp
        local_dest = GGUF_DIR / f"{hash_id}.gguf"
        import shutil
        shutil.copy2(gguf_path, local_dest)
        print(f"  ✅ Catalog updated. Binary at: {local_dest}")
        print(f"     kubectl cp {local_dest} spore/<bot-pod>:/data/spore-bot/loras/{hash_id}.gguf")
    
    return True


def main():
    today = datetime.now()
    date_str = today.strftime("%b %d")
    
    print(f"=== Mycelium Daily News Pipeline — {date_str} ===\n")
    
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    GGUF_DIR.mkdir(parents=True, exist_ok=True)
    
    # Check for base model (needed for GGUF conversion)
    base_model_dir = PIPELINE_DIR.parent / "training" / "base-model"
    if not base_model_dir.exists():
        base_model_dir = PIPELINE_DIR / "base-model"
        if not base_model_dir.exists():
            print("Downloading base model reference...")
            from huggingface_hub import snapshot_download
            snapshot_download(MODEL, local_dir=str(base_model_dir), ignore_patterns=["*.bin"])
    
    for source in SOURCES:
        print(f"\n📰 {source['name']}")
        print(f"   Feed: {source['feed_url']}")
        
        # 1. Fetch articles
        articles = fetch_articles(source["feed_url"])
        if not articles:
            print("   ⚠️  No articles found, skipping")
            continue
        print(f"   Found {len(articles)} articles")
        
        # 2. Format training data
        pairs = format_training_data(articles, source["name"])
        print(f"   Generated {len(pairs)} training pairs")
        
        # 3. Write training files
        data_dir = OUTPUT_DIR / source["slug"] / "data"
        n_train = write_training_files(pairs, data_dir)
        print(f"   Training set: {n_train} examples")
        
        # 4. Train LoRA
        adapter_dir = OUTPUT_DIR / source["slug"] / "adapter"
        if not train_lora(data_dir, adapter_dir, iters=500):
            continue
        
        # 5. Convert to GGUF
        gguf_path = GGUF_DIR / f"{source['slug']}-{today.strftime('%Y%m%d')}.gguf"
        if not convert_to_gguf(adapter_dir, gguf_path, base_model_dir):
            continue
        
        print(f"   GGUF: {gguf_path.name} ({gguf_path.stat().st_size // (1024*1024)} MB)")
        
        # 6. Publish to catalog
        publish_to_catalog(source, gguf_path, date_str)
    
    print(f"\n=== Pipeline complete ===")


if __name__ == "__main__":
    main()
