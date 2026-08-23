# 🎯 LeadSniper — Universal Autonomous Growth & Lead Acquisition Engine

**LeadSniper** is an autonomous real-time community radar that ingests live discussions from Reddit, forums, and community feeds to surface high-converting buyer/user leads and generate authentic, helpful non-spam responses with **1-Click Assisted Conversion**.

---

## ⚡ Key Highlights
* **Zero API Keys Required**: Ingests real-time Atom/RSS streams directly (100% bypasses rate limits & 403 API paywalls).
* **Multi-Project Workspaces**: Switch between unlimited products, SaaS tools, client agencies, or software with one click.
* **Intent & Pain-Point Scoring**: Automatically scores user intent (`🔥 HOT`, `⚡ WARM`, `❄️ COOL`) and filters out negative/disqualified queries.
* **Multi-Persona Response Engine**: Generates contextually aware replies with 100% clean, unbracketed direct product URLs.
* **1-Click Anti-Ban Workflow**: Single-click "Copy & Open" puts the human in the loop, completely eliminating captchas and bot bans.

---

## 🚀 Quickstart

### 1. Launch the Desktop Control Center (GUI)
```bash
python3 gui.py
# or
python3 app.py
```

### 2. Run in Automated Terminal Mode
```bash
# Scan default active project
python3 app.py --cli

# Scan specific project preset
python3 app.py --project saas_growth
```

### 3. Run Unit Tests
```bash
python3 -m unittest test_leadsniper.py
```

---

## 📁 Project Structure

```
leadsniper/
├── app.py                 # Master CLI & launcher entrypoint
├── gui.py                 # Dark-mode modern Desktop Radar & Control Center
├── test_leadsniper.py     # Comprehensive automated test suite
├── presets/               # Product presets (JSON)
│   ├── sunoget.json       # SunoGet AI Music Studio
│   ├── generic_saas.json  # Micro-SaaS & Indie Products
│   └── video_ai_tool.json # Video Editing & Caption Tools
└── core/                  # Engine modules
    ├── project_manager.py # Multi-project workspace switcher
    ├── rss_harvester.py   # Zero-API real-time feed parser
    ├── intent_analyzer.py # Intent scoring & negative filters
    └── persona_engine.py  # Authentic reply generator (clean URLs)
```

---

## ⚙️ Adding a New Product in 30 Seconds

Create a new JSON file inside `presets/your_product.json`:

```json
{
  "id": "my_new_app",
  "name": "My New App",
  "product_url": "https://myapp.com",
  "subreddits": ["webdev", "Python", "OpenAI"],
  "keywords": ["tool", "recommend", "how to automate", "alternative"],
  "negative_keywords": ["scam", "spam"],
  "features": [
    { "name": "Auto Sync", "trigger_words": ["sync", "cloud", "backup"] }
  ],
  "personas": [
    {
      "id": "friendly_peer",
      "name": "🚀 Helpful Creator",
      "template": "Hey u/{author}! If you're looking to {action_phrase} for \"{title}\", check out {url}. Hope this helps!"
    }
  ]
}
```

LeadSniper will automatically detect it in the dropdown!
