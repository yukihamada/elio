# TODO — elio

## P2P Infrastructure
- [ ] PrivateServerManager: friend request/acceptance handling (line 252-255)
- [ ] PrivateServerManager: trust list implementation (line 345)
- [ ] PrivateServerManager: friends list implementation (line 349)
- [ ] PrivateServerManager: payment verification with TokenManager (line 366)
- [ ] PrivateServerManager: get modelName from AppState (line 556)
- [ ] MeshP2PManager: multi-hop routing from peer announcements (line 148)
- [ ] P2PBackend: message signing (line 159)
- [ ] ProximityDiscoveryManager: QR code P2PServer construction (line 186)
- [ ] ProximityDiscoveryManager: bridge proximity devices to P2PBackend (line 195)
- [ ] SpeculativeVerifier: probability-based verification (line 100)
- [ ] ChatModeManager: configure speculative backend draft model (line 66)

## Core / Stability
- [ ] AgentOrchestrator: fix multi-turn conversation freeze bug (line 129) **HIGH PRIORITY**
- [ ] DeviceIdentityManager: P2P discovery by pairing code (line 134)

## elio-api Alignment
- [ ] CuratorManager: EIP-191 signature verification (line 231) **FIXME**
- [ ] CuratorManager: persist userId from LoginResponse (line 291)
- [ ] CuratorManager: add missing API endpoint in elio-api (line 375)

## Social Features
- [ ] FriendsManager: discover device by pairing code (line 31)
- [ ] FriendsManager: send friend request via P2P (line 100)
- [ ] FriendsManager: send acceptance via P2P (line 125)
- [ ] MessagingManager: queue messages for later delivery (line 73)

## UI / UX
- [ ] OnboardingView: re-enable KnowledgeBaseManager integration (line 24, 214, 223)
- [ ] MCPServerListView: implement server addition (line 448)
- [ ] MCPServerListView: implement file import (line 453)
- [ ] Maps/OfflineMapManager: MapLibre or Mapbox integration (line 206)
- [ ] Barter/BarterBoardManager: mesh network broadcast (line 212)
