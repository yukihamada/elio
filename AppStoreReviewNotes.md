# App Store Review Notes for ElioChat

## App Description
ElioChat is an AI-powered chat application that offers multiple inference modes:

### Chat Modes
1. **Local Mode** (Free)
   - On-device AI inference using CoreML
   - No internet required
   - Complete privacy - data never leaves the device

2. **Private Mode** (Free)
   - Connect to trusted devices on the same network via Bonjour
   - Uses local network permission for device discovery
   - User must explicitly trust devices before connecting

3. **Fast Mode** (1 token/message)
   - Uses Groq API for ultra-fast inference
   - Requires user's own API key from groq.com
   - API key stored securely in iOS Keychain

4. **Genius Mode** (5 tokens/message)
   - Uses premium cloud APIs (OpenAI GPT-4o, Anthropic Claude, Google Gemini)
   - Requires user's own API key from respective providers
   - API key stored securely in iOS Keychain

5. **Public Mode** (2 tokens/message)
   - Connect to community P2P servers
   - Uses Bonjour for server discovery

## Token System
- New users receive 100 free tokens
- Tokens can be purchased via subscription:
  - Basic: ¥500/month (1,000 tokens)
  - Pro: ¥1,500/month (5,000 tokens)
- Users can earn tokens by running a P2P server

## API Keys
- Users must obtain their own API keys from:
  - Groq: https://console.groq.com
  - OpenAI: https://platform.openai.com
  - Anthropic: https://console.anthropic.com
  - Google AI: https://makersuite.google.com

## Permissions Used
- **Camera**: For taking photos to send to AI
- **Microphone**: For voice input (speech-to-text)
- **Photos**: For selecting images to send to AI
- **Contacts**: For AI assistant to search contacts
- **Calendar**: For AI assistant to manage events
- **Reminders**: For AI assistant to create reminders
- **Location**: For AI assistant to get current location
- **Local Network**: For P2P device discovery

## Test Account
For testing subscription features, please use:
- Sandbox Apple ID: (Create in App Store Connect)

## Notes for Reviewers
1. Local Mode works without any API keys or internet
2. To test cloud modes, you'll need to enter API keys in Settings
3. P2P modes require two devices on the same network
4. The app does not store or transmit conversation data to our servers

## Privacy
- All conversation data is stored locally on device
- API keys are encrypted in iOS Keychain
- We do not collect any personal information
- See Privacy Policy in app: Settings > Privacy Policy

## Contact
Email: support@elio.love
