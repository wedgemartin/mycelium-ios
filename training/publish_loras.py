#!/usr/bin/env python3
"""
publish_loras.py — Upload demo LoRA adapters to the Sporebot catalog.

Connects to the Spore substrate and publishes LoRA metadata + binaries
so they're available for Mycelium clients to discover and download.

Usage:
    python3 publish_loras.py
"""

import json
import base64
import os
import sys
import urllib.request

# Configuration
SUBSTRATE_URL = os.environ.get("SUBSTRATE_URL", "https://ugov.xyz/api")
BOT_PUBKEY = "spore16h0gj58dpjxrr5fdg0y7gmy3a7k78cvjac6v9akurhp7tgs60h5sxaq2sm"

# Demo LoRAs to publish
LORAS = [
    {
        "file": "gguf/saopaulo-food.gguf",
        "name": "São Paulo Cuisine",
        "tags": ["sao paulo", "food", "cuisine", "brazilian", "restaurants", "padaria"],
        "base_model": "SmolLM2-1.7B-Instruct-Q4_K_M",
        "rank": 8,
        "lat": -23.55,
        "lng": -46.63,
    },
    {
        "file": "gguf/saopaulo-slang.gguf",
        "name": "São Paulo Slang",
        "tags": ["sao paulo", "slang", "brazilian", "portuguese", "gírias", "language"],
        "base_model": "SmolLM2-1.7B-Instruct-Q4_K_M",
        "rank": 8,
        "lat": -23.55,
        "lng": -46.63,
    },
    {
        "file": "gguf/saopaulo-events.gguf",
        "name": "São Paulo Current Events",
        "tags": ["sao paulo", "events", "news", "traffic", "local", "current"],
        "base_model": "SmolLM2-1.7B-Instruct-Q4_K_M",
        "rank": 8,
        "lat": -23.55,
        "lng": -46.63,
    },
    {
        "file": "gguf/california-slang.gguf",
        "name": "California Slang",
        "tags": ["california", "slang", "english", "bay area", "socal", "language"],
        "base_model": "SmolLM2-1.7B-Instruct-Q4_K_M",
        "rank": 8,
        "lat": 37.77,
        "lng": -122.42,
    },
    {
        "file": "gguf/california-seasonal.gguf",
        "name": "California Seasonal Food",
        "tags": ["california", "food", "seasonal", "produce", "farmers market", "foraging"],
        "base_model": "SmolLM2-1.7B-Instruct-Q4_K_M",
        "rank": 8,
        "lat": 37.77,
        "lng": -122.42,
    },
]


def compute_hash(data: bytes) -> str:
    """Simple hash for LoRA identification."""
    import hashlib
    return hashlib.blake2b(data, digest_size=16).hexdigest()


def publish_via_http(lora_info: dict, binary_data: bytes, hash_id: str):
    """
    Publish LoRA directly to the bot's MongoDB via substrate API.
    Falls back to a direct MongoDB insert if the API isn't available.
    """
    payload = {
        "type": "lora_publish",
        "hash": hash_id,
        "name": lora_info["name"],
        "tags": lora_info["tags"],
        "base_model": lora_info["base_model"],
        "rank": lora_info["rank"],
        "size_mb": len(binary_data) // (1024 * 1024),
        "lat": lora_info["lat"],
        "lng": lora_info["lng"],
        "binary": base64.b64encode(binary_data).decode("ascii"),
    }
    return payload


def publish_via_mongo(lora_info: dict, binary_data: bytes, hash_id: str):
    """Publish metadata to MongoDB + binary to bot's filesystem via SSH."""
    try:
        from pymongo import MongoClient
    except ImportError:
        print("  pymongo not installed, can't publish directly to MongoDB")
        return False

    mongo_uri = os.environ.get("MONGO_URI", "mongodb://172.30.1.74:27017")
    client = MongoClient(mongo_uri)
    db = client["spore"]

    # Insert catalog entry (metadata only)
    catalog_doc = {
        "hash": hash_id,
        "name": lora_info["name"],
        "tags": lora_info["tags"],
        "base_model": lora_info["base_model"],
        "rank": lora_info["rank"],
        "size_mb": len(binary_data) // (1024 * 1024),
        "author": BOT_PUBKEY,
        "location": {"type": "Point", "coordinates": [lora_info["lng"], lora_info["lat"]]},
    }
    db.lora_catalog.update_one(
        {"hash": hash_id}, {"$setOnInsert": catalog_doc}, upsert=True
    )

    # Write binary to local file (for SCP to bot pod later)
    os.makedirs("publish_binaries", exist_ok=True)
    binary_path = f"publish_binaries/{hash_id}.gguf"
    with open(binary_path, "wb") as f:
        f.write(binary_data)

    return True


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    print("=== Publishing LoRAs to Sporebot ===\n")

    # Try MongoDB direct first (fastest, works if you have tunnel/access)
    use_mongo = "--mongo" in sys.argv or os.environ.get("MONGO_URI")

    for lora in LORAS:
        filepath = lora["file"]
        if not os.path.exists(filepath):
            print(f"  ⚠️  {filepath} not found, skipping")
            continue

        with open(filepath, "rb") as f:
            binary_data = f.read()

        hash_id = compute_hash(binary_data)
        size_mb = len(binary_data) / (1024 * 1024)

        print(f"  📦 {lora['name']}")
        print(f"     Hash: {hash_id}")
        print(f"     Size: {size_mb:.1f} MB")
        print(f"     Tags: {', '.join(lora['tags'])}")
        print(f"     Region: {lora['lat']}, {lora['lng']}")

        if use_mongo:
            if publish_via_mongo(lora, binary_data, hash_id):
                print(f"     ✅ Published to MongoDB")
            else:
                print(f"     ❌ Failed")
        else:
            # Save the publish payload as JSON for manual upload or API call
            payload = publish_via_http(lora, binary_data, hash_id)
            out_file = f"publish_{hash_id[:8]}.json"
            with open(out_file, "w") as f:
                json.dump(payload, f)
            print(f"     💾 Saved payload to {out_file} (use --mongo to publish directly)")

        print()

    if not use_mongo:
        print("To publish directly to MongoDB, run:")
        print("  MONGO_URI='mongodb://...' python3 publish_loras.py --mongo")
        print()
        print("Or SSH tunnel to your MongoDB host first:")
        print("  ssh -L 27017:172.30.1.74:27017 emergency.shutdown.com")
        print("  MONGO_URI='mongodb://localhost:27017' python3 publish_loras.py --mongo")


if __name__ == "__main__":
    main()
