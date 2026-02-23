<p align="center">
  <img src="LocalAIAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" height="128" alt="ElioChat App Icon">
</p>

<h1 align="center">ElioChat</h1>

<p align="center">
  <strong>Your secret-keeping second brain</strong>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/elio-chat/id6757635481">
    <img src="https://img.shields.io/badge/App_Store-Download-blue?logo=apple&logoColor=white" alt="App Store">
  </a>
  <a href="https://elio.love">
    <img src="https://img.shields.io/badge/website-elio.love-purple" alt="Website">
  </a>
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <a href="README.ja.md">日本語</a> | <strong>English</strong>
</p>

---

## Overview

**ElioChat** is a fully local AI assistant app that runs entirely on your iPhone or iPad. It works without an internet connection, completely protects your privacy, and integrates with iOS features like Calendar, Reminders, Contacts, and Photos.

### Why ElioChat? - Safer than ChatGPT

| | ElioChat | ChatGPT |
|-----|------|---------|
| **Offline** | Works in Airplane Mode | Requires Internet |
| **Data Transmission** | Zero (fully local) | Sent to cloud |
| **Used for AI Training** | Never | May be used |
| **Enterprise Use** | OK even if ChatGPT is banned | Depends on policy |
| **Privacy** | Stays on device only | Stored on servers |
| **MCP Support** | 13 integrations | Not supported |
| **P2P Inference** | iPhone-Mac collaboration | Not supported |

---

## Features

### Local LLM Inference

| Category | Models | Size Range |
|----------|--------|------------|
| **Recommended** | Qwen3 (0.6B-8B), Gemma 3 (1B-4B), Phi-4 Mini | 500MB-5GB |
| **Japanese** | TinySwallow 1.5B, ELYZA Llama 3 8B, Swallow 8B | 1GB-5.2GB |
| **Vision** | Qwen3-VL (2B-8B), SmolVLM 2B | 1.1GB-5GB |
| **Efficient** | LFM2 (350M-1.2B), Jan Nano (128K/1M context) | 350MB-731MB |

- Fast inference with llama.cpp (GGUF format)
- Real-time download progress with speed & ETA
- Device-optimized model recommendations

### MCP (Model Context Protocol) Integration

ElioChat is the **first iOS app** to support Anthropic's [Model Context Protocol](https://modelcontextprotocol.io/), connecting AI with iOS system features:

| Server | Function |
|--------|----------|
| Calendar | View, create, delete events |
| Reminders | Manage reminders |
| Contacts | Search and view contacts |
| Location | Get current location |
| Photos | Access photo library |
| FileSystem | Read and write documents |
| Web Search | Anonymous DuckDuckGo search |

### P2P Inference (iPhone-Mac)

Offload heavy AI inference to your Mac over local network:

- **Bonjour Discovery** - Automatic Mac detection on the same network
- **Secure Pairing** - 4-digit code verification for trusted connections
- **Auto-reconnect** - Trusted devices reconnect automatically on app launch
- **Speculative Decoding** - Run small model locally + large model on Mac for faster output
- **Private Server** - Mac runs as a private inference server via `_eliochat._tcp`
- **Mesh Networking** - Multiple devices can form a P2P inference mesh

### Chat Modes

| Mode | Description |
|------|-------------|
| **Local** | On-device inference only (fully offline) |
| **Cloud** | ChatWeb API / Groq cloud backends |
| **Private P2P** | Connect to your Mac for powerful inference |
| **P2P Mesh** | Multi-device collaborative inference |
| **Speculative** | Local draft + remote verify for speed |

### Vision (Image Recognition)

- Attach images and ask AI questions about them
- Analyze photos taken with your camera
- Supports Qwen3-VL (2B/4B/8B) and SmolVLM models
- Automatic vision model download suggestions

### Voice Input

- On-device speech recognition with WhisperKit
- Japanese & English support
- Models cached locally after first download

### UI/UX

- Dark/Light mode support
- Real-time streaming display
- Conversation history management
- **Conversation search** - Find past conversations instantly
- **Share cards** - Create beautiful images to share on social media
- **Export conversations** - Save as text or JSON
- **Siri Shortcuts** - "Hey Siri, ask ElioChat"

---

## Installation

### From App Store

Download from the [App Store](https://apps.apple.com/app/elio-chat/id6757635481) (free, no ads).

### Build from Source

**Requirements**: iOS 17.0+, Xcode 15.0+

```bash
git clone https://github.com/yukihamada/LocalAIAgent.git
cd LocalAIAgent
open ElioChat.xcodeproj
```

1. Configure Signing & Capabilities in Xcode
2. Connect your device and Run (Cmd+R)

### Running Tests

```bash
# Unit tests (135 tests)
xcodebuild test -project ElioChat.xcodeproj -scheme ElioChat \
  -testPlan UnitTests -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Supported Models

30+ GGUF format models organized by category:

### Recommended
| Model | Size | Best For |
|-------|------|----------|
| Qwen3 0.6B | ~500MB | All devices, ultra-fast |
| Qwen3 1.7B | ~1.2GB | All devices, balanced |
| Qwen3 4B | ~2.7GB | Pro devices, high performance |
| Qwen3 8B | ~5GB | Pro Max, best quality |
| Gemma 3 1B | ~700MB | All devices, Google's latest |
| Gemma 3 4B | ~2.5GB | Pro devices, excellent |
| Phi-4 Mini | ~2.4GB | Pro devices, best at reasoning |

### Japanese Optimized
| Model | Size | Notes |
|-------|------|-------|
| TinySwallow 1.5B | ~986MB | Sakana AI, high quality |
| ELYZA Llama 3 8B | ~5.2GB | UTokyo Matsuo Lab, top tier |
| Swallow 8B | ~5.2GB | Tokyo Tech, business docs |

### Vision Models
| Model | Size | Notes |
|-------|------|-------|
| Qwen3-VL 2B | ~1.1GB | All devices |
| Qwen3-VL 4B | ~2.5GB | Pro devices |
| Qwen3-VL 8B | ~5GB | Pro Max, best quality |

---

## Architecture

```
LocalAIAgent/
├── App/                    # Application layer
│   ├── LocalAIAgentApp.swift
│   ├── AppState.swift      # Global state management
│   └── AppIntents.swift    # Siri Shortcuts
├── Agent/                  # AI Agent orchestration
│   ├── AgentOrchestrator.swift
│   ├── ConversationManager.swift
│   └── ToolParser.swift
├── LLM/                    # Inference engine
│   ├── ModelLoader.swift   # Model management & download
│   ├── CoreMLInference.swift
│   ├── WhisperManager.swift
│   └── Tokenizer.swift
├── ChatModes/              # Multi-backend chat system
│   ├── ChatModeManager.swift
│   ├── Backends/           # Local, Cloud, P2P, Speculative
│   └── P2PServer/          # Private server & mesh networking
├── Discovery/              # Device discovery (Bonjour/QR)
├── MCP/                    # Model Context Protocol
│   ├── MCPClient.swift
│   └── Servers/            # Calendar, Reminders, Contacts, etc.
├── Security/               # Device identity & keychain
├── TokenEconomy/           # Subscriptions & token management
├── Views/                  # SwiftUI views
└── Resources/              # Assets & localization
```

---

## Privacy

ElioChat is designed with privacy first.

- **All processing happens on device**
- **No data sent to external servers**
- **Conversation history stored only on device**
- **P2P connections stay on local network**
- **Open source** - verify the code yourself

### Required Permissions

| Permission | Purpose |
|------------|---------|
| Calendar | Read/write events |
| Reminders | Manage reminders |
| Contacts | Search contacts |
| Location | Get current location |
| Photos | Load/save images |
| Microphone | Voice input |
| Local Network | P2P device discovery |

All permissions are requested only when needed.

---

## Contributing

Pull requests are welcome!

1. Fork this repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Links

- [Website](https://elio.love)
- [Privacy Policy](https://elio.love/privacy)
- [Terms of Service](https://elio.love/terms)

## Acknowledgments

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - GGUF inference engine
- [Model Context Protocol](https://modelcontextprotocol.io/) - AI integration protocol
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - On-device speech recognition

---

<p align="center">
  Made with love by <a href="https://github.com/yukihamada">yukihamada</a>
</p>
