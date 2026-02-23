<p align="center">
  <img src="LocalAIAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" height="120" alt="ElioChat">
</p>

<h1 align="center">ElioChat</h1>

<p align="center">
  <strong>Your secret-keeping second brain.</strong><br>
  Completely free, no ads, fully offline private AI chat
</p>

<p align="center">
  <a href="https://apps.apple.com/app/elio-chat/id6757635481">
    <img src="https://img.shields.io/badge/App_Store-Free_Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="App Store">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0+-000000?style=flat-square&logo=apple" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/Models-30%2B-blue?style=flat-square" alt="30+ Models">
  <img src="https://img.shields.io/badge/MCP-13_servers-purple?style=flat-square" alt="MCP">
</p>

<p align="center">
  <a href="README.md">日本語</a> | <strong>English</strong>
</p>

---

## Screenshots

<p align="center">
  <img src="fastlane/screenshots_final/en-US/iPhone 16 Pro Max-01_WelcomeScreen.png" width="19%" alt="Welcome">
  <img src="fastlane/screenshots_final/en-US/iPhone 16 Pro Max-02_ChatSchedule.png" width="19%" alt="Schedule">
  <img src="fastlane/screenshots_final/en-US/iPhone 16 Pro Max-03_ChatCode.png" width="19%" alt="Code">
  <img src="fastlane/screenshots_final/en-US/iPhone 16 Pro Max-05_ChatPrivacy.png" width="19%" alt="Privacy">
  <img src="fastlane/screenshots_final/en-US/iPhone 16 Pro Max-08_Settings.png" width="19%" alt="Models">
</p>

---

## What Can ElioChat Do?

### 1. Chat with AI in Airplane Mode

```
You: Summarize today's meeting notes

ElioChat: Sure. Here's a summary:
  Date: Feb 23, 14:00-15:00
  Attendees: Tanaka, Sato, Yamada
  Agenda: Q1 sales report...
```

No internet needed. Works on planes, subways, and anywhere offline.
All processing runs on your iPhone. No data ever leaves your device.

### 2. Control Calendar & Reminders with AI

```
You: What's on my schedule today?

ElioChat: I checked your calendar. Today's events:
  10:00 - Team Meeting
  12:00 - Lunch with Sarah
  14:00 - Project Review
  16:00 - Client Call
```

```
You: Remind me to take out the trash at 10am tomorrow

ElioChat: Reminder created:
  Take out trash - Tomorrow 10:00
```

Directly integrates with iOS Calendar, Reminders, Contacts, and Photos.
First iOS app to support [MCP (Model Context Protocol)](https://modelcontextprotocol.io/).

### 3. Choose from 30+ AI Models

| Recommended | Japanese | Vision |
|:-----------:|:--------:|:------:|
| Qwen3 (0.6B-8B) | TinySwallow 1.5B | Qwen3-VL (2B-8B) |
| Gemma 3 (1B-4B) | ELYZA Llama 3 8B | SmolVLM 2B |
| Phi-4 Mini | Swallow 8B | |

Auto-recommends the best model for your device. GGUF format for fast inference.

### 4. Ask AI About Photos

```
You: [attach photo] What flower is this?

ElioChat: This is a cherry blossom (Sakura).
  It typically blooms from late March to early April...
```

Analyze camera photos or library images instantly with Qwen3-VL / SmolVLM.

### 5. Voice Input

On-device speech recognition with WhisperKit. Japanese & English. Voice data never leaves your device.

### 6. Borrow Your Mac's Power (P2P Inference)

```
┌──────────┐     WiFi / LAN      ┌──────────┐
│  iPhone  │ <------------------> │   Mac    │
│ Small LLM │  Bonjour Discovery  │ Large LLM│
│  drafts   │  Encrypted P2P      │ verifies │
└──────────┘                     └──────────┘
```

- Auto-discover Macs on your local network
- Secure pairing with 4-digit code
- Auto-reconnect on next launch
- Speculative decoding for faster output

---

## ElioChat vs ChatGPT

|  | ElioChat | ChatGPT |
|:---|:---:|:---:|
| Offline | Airplane Mode OK | Internet required |
| Data Transmission | Zero | Sent to cloud |
| Used for AI Training | Never | May be used |
| Enterprise Use | OK even if ChatGPT banned | Policy dependent |
| Data Storage | On device only | On servers |
| MCP Integration | 13 types | Not supported |
| P2P Inference | Mac collaboration | Not supported |
| Price | Completely free | $20/month |

---

## For Developers

### Build

```bash
git clone https://github.com/yukihamada/elio.git
cd elio
open ElioChat.xcodeproj
```

### Test

```bash
xcodebuild test -project ElioChat.xcodeproj -scheme ElioChat \
  -testPlan UnitTests -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Architecture

```
LocalAIAgent/
├── App/            Application layer (AppState, Siri Shortcuts)
├── Agent/          AI Agent (Orchestrator, ToolParser)
├── LLM/            Inference engine (llama.cpp, WhisperKit)
├── ChatModes/      Multi-backend (Local, Cloud, P2P, Speculative)
│   ├── Backends/   Backend implementations
│   └── P2PServer/  Private server & mesh networking
├── Discovery/      Device discovery (Bonjour / QR)
├── MCP/            Model Context Protocol (13 servers)
├── Security/       Device identity & keychain
├── Views/          SwiftUI views
└── Resources/      Assets & localization
```

---

## Links

| | |
|:--|:--|
| Website | [elio.love](https://elio.love) |
| App Store | [Download](https://apps.apple.com/app/elio-chat/id6757635481) |
| Privacy Policy | [elio.love/privacy](https://elio.love/privacy) |
| Terms of Service | [elio.love/terms](https://elio.love/terms) |

## License

MIT License - [LICENSE](LICENSE)

---

<p align="center">
  Made with love by <a href="https://github.com/yukihamada">yukihamada</a>
</p>
