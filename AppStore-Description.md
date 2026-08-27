# Mycelium — App Store Connect Listing

## App Name
Mycelium

## Subtitle (30 chars max)
On-Device AI, Shared Knowledge

## Promotional Text (170 chars max)
Run AI privately on your device. Download community knowledge adapters over a peer-to-peer network. On Mac, train and share your own. No cloud, no API keys.

## Description

Mycelium runs AI directly on your device — no cloud, no subscriptions, no data leaving your phone. Ask questions and get answers enhanced by community knowledge that spreads peer-to-peer.

ON-DEVICE AI
A language model runs entirely on your device using GPU acceleration. Your conversations are private — nothing is sent to any server.

COMMUNITY KNOWLEDGE ADAPTERS
Lightweight knowledge modules (LoRA adapters) specialize the AI for a topic — local slang, regional food, transit tips, daily news. They download automatically when relevant to your question, typically 10-50MB each.

PEER-TO-PEER SHARING
Adapters propagate through geographic gossip over the Spore protocol. Discover what nearby peers know. No central server decides what's relevant.

TRAIN YOUR OWN (macOS)
On Mac, create custom adapters from your own data — RSS feeds, text files, or pasted content. Test them with a rating system, then optionally share to the network. Your training data never leaves your device.

DYNAMIC ROUTING
Ask a question and Mycelium finds, downloads, and activates the most relevant adapters automatically. Knowledge compounds.

TEXT-TO-SPEECH
Toggle voice mode and hear answers spoken aloud as they generate.

WORKS OFFLINE
Once downloaded, everything runs locally. Chat anywhere — airplane mode, underground, off-grid.

SAFETY & MODERATION
Every shared adapter can be reported or blocked in-app. Objectionable content is removed from the network. We maintain a zero-tolerance policy for content that exploits minors, promotes hate, or facilitates illegal activity.

Privacy Policy: https://mycelium.getspore.xyz/privacy.html
Terms of Service: https://mycelium.getspore.xyz/terms.html
Safety & Content Policy: https://mycelium.getspore.xyz/safety.html
Support: https://mycelium.getspore.xyz/support.html

## Keywords (100 chars max)
AI,local,private,LLM,offline,on-device,knowledge,adapter,peer-to-peer,assistant,chat,training

## Support URL
https://mycelium.getspore.xyz/support.html

## Marketing URL
https://mycelium.getspore.xyz

## Privacy Policy URL
https://mycelium.getspore.xyz/privacy.html

---

## AGE RATING: 17+

Set the following in App Store Connect → App Information → Age Rating:

Recommend **17+** because the app enables user-generated content (LoRA adapters) shared over a P2P network and produces AI-generated text that is not pre-moderated. Answer the age rating questionnaire as follows:

- **Unrestricted Web Access:** No (the app doesn't browse the web)
- **User-Generated Content:** Yes — Frequent/Intense
  - Note: Mycelium includes in-app reporting, blocking, and content filtering per Apple Guideline 1.2
- **Medical/Treatment Info:** No
- **Gambling/Contests:** No
- **Mature/Suggestive Themes:** Infrequent/Mild (AI can generate varied text)
- All violence/sexual/drug categories: None

## App Review Notes (paste into App Store Connect → App Review Information → Notes)

Mycelium is an on-device AI app. All AI inference runs locally using Metal GPU — no cloud processing.

Users can download small "LoRA adapter" files (AI knowledge modules) shared peer-to-peer over the Spore protocol, and on macOS can train and publish their own.

UGC SAFETY COMPLIANCE (Guideline 1.2):
- In-app REPORT action on every network adapter (swipe left → Report). Reports reduce the adapter's network reputation and hide it locally; 7+ reports auto-removes it from the network.
- In-app BLOCK action (swipe left → Block) hides all adapters from a publisher permanently.
- Content filtering: blocked/hidden adapters are excluded from the catalog on every sync.
- Published Content Policy: https://mycelium.getspore.xyz/safety.html
- CSAM zero-tolerance with NCMEC reporting commitment.
- Safety contact: safety@getspore.xyz (24-hour review SLA).

The first launch downloads a ~1GB base model from HuggingFace. Please test on WiFi.

## What's New (Version 1.1)
• Train custom knowledge adapters on Mac from RSS feeds, text, or files
• Test & rate adapters before publishing to improve quality
• Report and block adapters directly in-app
• Upvote/downvote community adapters
• Text-to-speech with live streaming
• macOS native support
• Model selection based on your device
