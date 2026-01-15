<p align="center">
  <img src="LocalAIAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" height="128" alt="ElioChat App Icon">
</p>

<h1 align="center">ElioChat</h1>

<p align="center">
  <strong>Your secret-keeping second brain</strong>
</p>

<p align="center">
  <a href="https://elio.love">Website</a> •
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#supported-models">Models</a> •
  <a href="#mcp-integration">MCP</a> •
  <a href="#privacy">Privacy</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/website-elio.love-purple" alt="Website">
</p>

<p align="center">
  <a href="README.ja.md">日本語</a> | <strong>English</strong>
</p>

---

## Overview

**ElioChat** is a fully local AI assistant app that runs entirely on your iPhone. It works without an internet connection, completely protects your privacy, and integrates with iOS features like Calendar, Reminders, Contacts, and Photos.

### Why ElioChat? - Safer than ChatGPT

| | ElioChat | ChatGPT |
|-----|------|---------|
| **Offline** | Works in Airplane Mode | Requires Internet |
| **Data Transmission** | Zero (fully local) | Sent to cloud |
| **Used for AI Training** | Never | May be used |
| **Enterprise Use** | OK even if ChatGPT is banned | Depends on policy |
| **Privacy** | Stays on device only | Stored on servers |

- **MCP Support** - Integrates with system features via Model Context Protocol
- **30+ Models** - Choose from Qwen3, Gemma 3, Phi-4, Llama 3.2, and more
- **Vision AI** - Image recognition with Qwen3-VL models
- **Voice Input** - On-device speech recognition with WhisperKit
- **Japanese Support** - Full Japanese UI and AI responses

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

ElioChat connects AI with iOS system features:

| Server | Function |
|--------|----------|
| Calendar | View, create, delete events |
| Reminders | Manage reminders |
| Contacts | Search and view contacts |
| Location | Get current location |
| Photos | Access photo library |
| FileSystem | Read and write documents |
| Web Search | Anonymous DuckDuckGo search |

### Vision (Image Recognition)

- Attach images and ask AI questions about them
- Analyze photos taken with your camera
- Supports Qwen3-VL (2B/4B/8B) and SmolVLM models
- Automatic vision model download suggestions

### Voice Input

- On-device speech recognition with WhisperKit
- Japanese & English support
- Download progress indicator
- Models cached locally after first download

### UI/UX

- Dark/Light mode support
- Swipe-based onboarding
- Real-time streaming display
- Conversation history management
- **Conversation search** - Find past conversations instantly
- **Share cards** - Create beautiful images to share on social media
- **Export conversations** - Save as text or JSON

### Siri Shortcuts

Control ElioChat with your voice:
- "Hey Siri, ask ElioChat" - Start a conversation
- "Hey Siri, check my schedule with ElioChat" - View calendar
- "Hey Siri, create reminder with ElioChat" - Add a reminder

### Referral Program

Share ElioChat with friends:
- Generate your unique referral code
- Share with one tap
- Track how many friends joined

---

## Installation

### Requirements

- iOS 17.0 or later
- iPhone or iPad (arm64)
- Xcode 15.0 or later

### Build Steps

```bash
# Clone the repository
git clone https://github.com/yukihamada/LocalAIAgent.git
cd LocalAIAgent

# Open in Xcode
open ElioChat.xcodeproj
```

1. Configure Signing & Capabilities in Xcode
2. Connect your device and Run (Cmd+R)

### Downloading Models

On first launch, you'll be guided through downloading:
- **Text model** - Qwen3 1.7B (recommended for most devices)
- **Vision model** - Qwen3-VL 2B (optional, for image recognition)

Additional models can be downloaded from Settings.

---

## Supported Models

ElioChat supports 30+ GGUF format models organized by category:

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

### Efficient / Long Context
| Model | Size | Context |
|-------|------|---------|
| LFM2 350M | ~350MB | 32K |
| LFM2 1.2B | ~731MB | 32K |
| Jan Nano 128K | ~500MB | 128K tokens |
| Jan Nano 1M | ~500MB | 1M tokens |

---

## MCP Integration

ElioChat uses Anthropic's [Model Context Protocol](https://modelcontextprotocol.io/) to seamlessly connect AI with iOS system features.

### Examples

```
User: Show me today's schedule

ElioChat: I checked your calendar. Here are today's events:
• 10:00 - 11:30 Weekly Design Meeting
• 13:00 - 14:00 Lunch with Sato-san
• 16:00 - 17:30 Project X Progress Review
```

```
User: Create a reminder for "Dentist" tomorrow at 10am

ElioChat: Reminder created:
  Dentist
  Tomorrow 10:00
```

---

## Privacy

ElioChat is designed with privacy first.

- **All processing happens on device**
- **No data sent to external servers**
- **Conversation history stored only on device**
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

All permissions are requested only when needed.

---

## Architecture

```
LocalAIAgent/
├── App/                    # Application layer
│   ├── LocalAIAgentApp.swift
│   ├── AppState.swift      # State management
│   └── AppIntents.swift    # Siri Shortcuts
├── Agent/                  # AI Agent
│   ├── AgentOrchestrator.swift
│   ├── ConversationManager.swift
│   └── ToolParser.swift
├── LLM/                    # Inference engine
│   ├── ModelLoader.swift   # Model management & download
│   ├── CoreMLInference.swift
│   ├── WhisperManager.swift # Voice recognition
│   └── Tokenizer.swift
├── MCP/                    # MCP Protocol
│   ├── MCPClient.swift
│   ├── MCPProtocol.swift
│   └── Servers/           # MCP server implementations
├── Services/              # Business logic
│   ├── ConversationExporter.swift
│   └── ReferralManager.swift
├── Views/                  # SwiftUI views
└── Resources/              # Assets & localization
```

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

## Acknowledgments

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - GGUF inference engine
- [Model Context Protocol](https://modelcontextprotocol.io/) - AI integration protocol
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - On-device speech recognition

---

<p align="center">
  Made with love by <a href="https://github.com/yukihamada">yukihamada</a>
</p>
