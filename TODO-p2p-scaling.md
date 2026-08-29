# Mycelium P2P Scaling Roadmap

**Tracked:** 2026-08-27

## Problem

Mycelium's current P2P is minimal — LAN-only mDNS (`_mycelium._udp`) with a basic
`LORA_LIST?` protocol. Everything else falls back to the sporebot over DERP.

As LoRA adapters grow to 15MB+ and number in the hundreds across thousands of users,
**bot-centric distribution becomes the bottleneck.** Every device pulling 15MB adapters
from the bot over DERP doesn't scale.

## Goal

Make Mycelium a real P2P content-distribution network (BitTorrent-like) where peers
serve LoRA adapters to each other.

## What's needed (to match Spore's networking maturity)

1. **Cross-internet P2P** (not just LAN) — STUN + hole-punching + IPv6 direct so a device
   can pull a LoRA from a nearby peer without the bot relaying 15MB.
2. **Global IPv6 endpoint registration** — WITH the site-local filter fix baked in from
   the start (reject `fec0::`/`fe80::`/`fc`/`fd`). See the Spore bug fixed 2026-08-27 in
   `GossipEngine.getIPv6Address()` and `DirectConnectionManager.discoverIPv6()`.
3. **Chunked P2P transfer** — 15MB adapter split across peers, resumable, no single peer
   bears the whole load.
4. **Peer selection by who-has-what** — catalog already tracks which peers have which
   adapter hashes; extend to prefer nearby peers with the adapter over the bot.
5. **Bot as seeder-of-last-resort** — only serve from bot when no peer has it (torrent seed).

## Approach

Spore already solved most of this. Port Spore's `PeerConnection` / `HolePunch` /
QUIC-direct machinery (in `spore-ios/Spore/Spore/Services/`) into Mycelium's
`PeerManager` (`mycelium-ios/Mycelium/Mycelium/Services/PeerManager.swift`).
Bring the IPv6 site-local filter fix along so it's correct from day one.

## Current state (fine for now)

Handful of small demo LoRAs + news LoRAs, bot seeds them, DERP handles it. Only becomes
urgent at scale (15MB adapters × hundreds × thousands of users).

## Notes

- Chunked transfer already exists for DERP (512KB chunks) in `NetworkManager` — the P2P
  version reuses that chunking logic over direct QUIC connections.
- Mycelium reuses Spore identity/transport concepts (Ed25519, bech32, QUIC, DERP fallback).
- Both platforms (iOS + macOS) share the codebase; Android (`mycelium-android`) would need
  the equivalent port from `spore-android`'s `DirectConnectionManager`.
