# Daily News LoRA Pipeline

Automated daily training of LoRA adapters from public news sources, published to the Spore network for Mycelium clients.

## How it works

```
6:00am  Scrape RSS feeds (NPR, PBS, AP News, Agência Brasil)
6:01am  Format articles into Q&A training pairs
6:02am  Train LoRA adapter (~20-30 min on CPU)
6:30am  Convert to GGUF
6:31am  Publish to Sporebot catalog
6:32am  Available to all Mycelium users worldwide
```

Every morning, your AI wakes up knowing what happened yesterday.

## Sources

| Source | Region | Feed |
|--------|--------|------|
| NPR News | United States | Top stories |
| PBS NewsHour | United States | Headlines |
| AP News | International | Top news |
| Agência Brasil | Brasil | Latest news (Portuguese) |

## Setup

```bash
pip install -r requirements.txt

# Set MongoDB URI (tunnel or direct)
export MONGO_URI="mongodb://localhost:27017"

# Run manually
python3 daily_news_lora.py

# Or set up cron (on your server)
0 6 * * * cd /opt/mycelium/pipeline && python3 daily_news_lora.py >> /var/log/mycelium-pipeline.log 2>&1
```

## Output

Each run produces:
- One LoRA per source (e.g., `npr-20260820.gguf`, `pbs-20260820.gguf`)
- Catalog entries in MongoDB with appropriate tags and geo coordinates
- Binary files copied to the bot's `/data/spore-bot/loras/` directory

## Adding Sources

Add a new entry to the `SOURCES` list in `daily_news_lora.py`:

```python
{
    "name": "BBC Brasil",
    "slug": "bbc-brasil",
    "feed_url": "https://www.bbc.com/portuguese/index.xml",
    "tags": ["news", "brasil", "international", "portuguese"],
    "lat": -23.55,
    "lng": -46.63,
}
```

## User Experience

When a Mycelium user asks "What happened in the news today?":
1. Model extracts tags: `["news", "current events", "today"]`
2. Matches against catalog → finds "NPR News - Aug 20"
3. Downloads 12MB adapter from Sporebot
4. Applies and answers with yesterday's headlines

The response footer shows: `🍄 via NPR News - Aug 20`
