<p align="center">
  <img src="LocalAIAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" height="128" alt="Elio App Icon">
</p>

<h1 align="center">Elio</h1>

<p align="center">
  <strong>Your secret-keeping second brain</strong>
</p>

<p align="center">
  <a href="https://elio.love">🌐 Website</a> •
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
  <a href="README.ja.md">🇯🇵 日本語</a> | <strong>🇺🇸 English</strong>
</p>

---

## Overview

**Elio** is a fully local AI assistant app that runs entirely on your iPhone. It works without an internet connection, completely protects your privacy, and integrates with iOS features like Calendar, Reminders, Contacts, and Health.

### Why Elio? - Safer than ChatGPT

| | Elio | ChatGPT |
|-----|------|---------|
| **Offline** | ✅ Works in Airplane Mode | ❌ Requires Internet |
| **Data Transmission** | ✅ Zero (fully local) | ❌ Sent to cloud |
| **Used for AI Training** | ✅ Never | ⚠️ May be used |
| **Enterprise Use** | ✅ OK even if ChatGPT is banned | ⚠️ Depends on policy |
| **Privacy** | ✅ Stays on device only | ❌ Stored on servers |

- **MCP Support** - Integrates with system features via Model Context Protocol
- **Multiple Models** - Choose from Qwen3, Llama 3.2, Gemma and more
- **Japanese Support** - Full Japanese UI and AI responses

---

## Features

### 🧠 Local LLM Inference

| Model | Size | Features |
|-------|------|----------|
| Qwen3 4B | ~2.7GB | High performance, excellent Japanese |
| Qwen3 8B | ~5GB | Best performance |
| Llama 3.2 3B | ~2GB | Lightweight & fast |
| Gemma 2 2B | ~1.5GB | Ultra lightweight |

- Fast inference with llama.cpp
- CoreML optimization (for supported models)
- Streaming output

### 🔌 MCP (Model Context Protocol) Integration

Elio connects AI with iOS system features:

| Server | Function |
|--------|----------|
| 📅 Calendar | View, create, delete events |
| ✅ Reminders | Manage reminders |
| 👥 Contacts | Search and view contacts |
| 📍 Location | Get current location |
| 🏥 Health | Read health data |
| 📷 Photos | Access photo library |
| 📁 FileSystem | Read and write documents |
| 🔍 Web Search | Anonymous DuckDuckGo search |

### 🖼️ Vision (Image Recognition)

- Attach images and ask AI questions about them
- Analyze photos taken with your camera
- Supports vision models (Llava, Qwen2-VL, etc.)

### 🎤 Voice Input

- On-device speech recognition with WhisperKit
- Japanese & English support
- Auto-downloads model on first use

### 🎨 UI/UX

- Dark/Light mode support
- Swipe-based onboarding
- Real-time streaming display
- Conversation history management
- Skeleton loading for fast perceived startup

---

## Installation

### Requirements

- iOS 17.0 or later
- iPhone (arm64)
- Xcode 15.0 or later

### Build Steps

```bash
# Clone the repository
git clone https://github.com/yukihamada/elio.git
cd elio

# Open in Xcode
open LocalAIAgent.xcodeproj
```

1. Configure Signing & Capabilities in Xcode
2. Connect your device and Run (⌘R)

### Downloading Models

You can download models from the Settings screen in the app. On first launch, you'll be prompted to download the recommended model (Qwen3 4B).

---

## Supported Models

Elio supports GGUF format models.

```
Recommended: Qwen3-4B-Q4_K_M.gguf
- Balanced performance
- Excellent Japanese responses
- ~2.7GB storage
```

### Supported Formats

- GGUF (llama.cpp)
- CoreML (select models)

---

## MCP Integration

Elio uses Anthropic's [Model Context Protocol](https://modelcontextprotocol.io/) to seamlessly connect AI with iOS system features.

### Examples

```
User: Show me today's schedule

Elio: I checked your calendar. Here are today's events:
• 10:00 - 11:30 Weekly Design Meeting
• 13:00 - 14:00 Lunch with Sato-san
• 16:00 - 17:30 Project X Progress Review
```

```
User: Create a reminder for "Dentist" tomorrow at 10am

Elio: Reminder created:
📋 Dentist
📅 Tomorrow 10:00
```

---

## Privacy

Elio is designed with privacy first.

- ✅ **All processing happens on device**
- ✅ **No data sent to external servers**
- ✅ **Conversation history stored only on device**
- ✅ **Open source** - verify the code yourself

### Required Permissions

| Permission | Purpose |
|------------|---------|
| Calendar | Read/write events |
| Reminders | Manage reminders |
| Contacts | Search contacts |
| Location | Get current location |
| Health | Read health data |
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
│   └── ThemeManager.swift
├── Agent/                  # AI Agent
│   ├── AgentOrchestrator.swift
│   ├── ConversationManager.swift
│   └── ToolParser.swift
├── LLM/                    # Inference engine
│   ├── LlamaInference.swift
│   ├── CoreMLInference.swift
│   ├── ModelLoader.swift
│   ├── WhisperManager.swift
│   └── Tokenizer.swift
├── MCP/                    # MCP Protocol
│   ├── MCPClient.swift
│   ├── MCPProtocol.swift
│   └── Servers/           # MCP server implementations
├── Models/                 # Data models
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
  Made with ❤️ by <a href="https://github.com/yukihamada">yukihamada</a>
</p>
