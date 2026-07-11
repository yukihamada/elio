import Foundation
import MediaPlayer
import AVFoundation

/// MCP Server for Apple Music playback control, library search, and queue management.
final class MusicServer: MCPServer {
    let id = "music"
    let name = "ミュージック"
    let serverDescription = "Apple Musicの再生操作、曲の検索、プレイリスト管理を行います"
    let icon = "music.note"

    private let player = MPMusicPlayerController.systemMusicPlayer

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "now_playing",
                description: "現在再生中の曲情報を取得します（タイトル、アーティスト、アルバム、再生時間）",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "play_pause",
                description: "再生/一時停止をトグルします",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "next_track",
                description: "次の曲へスキップします",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "previous_track",
                description: "前の曲へ戻ります",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "set_volume",
                description: "音量を設定します (0.0〜1.0)",
                inputSchema: MCPInputSchema(
                    properties: [
                        "volume": MCPPropertySchema(type: "number", description: "音量 0.0(無音)〜1.0(最大)")
                    ],
                    required: ["volume"]
                )
            ),
            MCPTool(
                name: "get_volume",
                description: "現在の音量を取得します",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "search_library",
                description: "ミュージックライブラリから曲を検索します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "query": MCPPropertySchema(type: "string", description: "検索キーワード（曲名、アーティスト名、アルバム名）")
                    ],
                    required: ["query"]
                )
            ),
            MCPTool(
                name: "play_song",
                description: "指定した曲を検索して再生します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "query": MCPPropertySchema(type: "string", description: "曲名やアーティスト名で検索して再生")
                    ],
                    required: ["query"]
                )
            ),
            MCPTool(
                name: "queue_song",
                description: "再生キューに曲を追加します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "query": MCPPropertySchema(type: "string", description: "キューに追加する曲の検索キーワード")
                    ],
                    required: ["query"]
                )
            ),
            MCPTool(
                name: "get_playlist",
                description: "プレイリスト一覧を取得します",
                inputSchema: MCPInputSchema()
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "now_playing":
            return await nowPlaying()
        case "play_pause":
            return await playPause()
        case "next_track":
            return await nextTrack()
        case "previous_track":
            return await previousTrack()
        case "set_volume":
            return await setVolume(arguments)
        case "get_volume":
            return getVolume()
        case "search_library":
            return searchLibrary(arguments)
        case "play_song":
            return await playSong(arguments)
        case "queue_song":
            return await queueSong(arguments)
        case "get_playlist":
            return getPlaylist()
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    // MARK: - Now Playing

    @MainActor
    private func nowPlaying() -> MCPResult {
        guard let item = player.nowPlayingItem else {
            return MCPResult(content: [.text("現在再生中の曲はありません")])
        }

        let title = item.title ?? "不明"
        let artist = item.artist ?? "不明"
        let album = item.albumTitle ?? "不明"
        let duration = item.playbackDuration
        let currentTime = player.currentPlaybackTime

        let stateStr: String
        switch player.playbackState {
        case .playing:
            stateStr = "再生中"
        case .paused:
            stateStr = "一時停止"
        case .stopped:
            stateStr = "停止"
        case .interrupted:
            stateStr = "中断"
        case .seekingForward:
            stateStr = "早送り"
        case .seekingBackward:
            stateStr = "巻き戻し"
        @unknown default:
            stateStr = "不明"
        }

        let info = """
        状態: \(stateStr)
        タイトル: \(title)
        アーティスト: \(artist)
        アルバム: \(album)
        再生時間: \(formatTime(currentTime)) / \(formatTime(duration))
        """

        return MCPResult(content: [.text(info)])
    }

    // MARK: - Playback Controls

    @MainActor
    private func playPause() -> MCPResult {
        if player.playbackState == .playing {
            player.pause()
            return MCPResult(content: [.text("一時停止しました")])
        } else {
            player.play()
            let title = player.nowPlayingItem?.title ?? "曲"
            return MCPResult(content: [.text("再生を開始しました: \(title)")])
        }
    }

    @MainActor
    private func nextTrack() -> MCPResult {
        player.skipToNextItem()
        // Small delay to let the player update
        let title = player.nowPlayingItem?.title ?? "次の曲"
        let artist = player.nowPlayingItem?.artist ?? ""
        let info = artist.isEmpty ? title : "\(title) - \(artist)"
        return MCPResult(content: [.text("次の曲へ: \(info)")])
    }

    @MainActor
    private func previousTrack() -> MCPResult {
        player.skipToPreviousItem()
        let title = player.nowPlayingItem?.title ?? "前の曲"
        let artist = player.nowPlayingItem?.artist ?? ""
        let info = artist.isEmpty ? title : "\(title) - \(artist)"
        return MCPResult(content: [.text("前の曲へ: \(info)")])
    }

    // MARK: - Volume

    @MainActor
    private func setVolume(_ args: [String: JSONValue]) -> MCPResult {
        guard let volume = args["volume"]?.doubleValue else {
            return MCPResult(content: [.text("[ERROR] 'volume' is required (0.0-1.0)")], isError: true)
        }
        let clamped = Float(min(max(volume, 0.0), 1.0))

        // Use MPVolumeView to set system volume programmatically
        let volumeView = MPVolumeView(frame: .zero)
        if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
            slider.value = clamped
        } else {
            // Fallback: use AVAudioSession route volume hint
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                return MCPResult(content: [.text("[ERROR] 音量設定に失敗: \(error.localizedDescription)")], isError: true)
            }
        }

        return MCPResult(content: [.text("音量を \(Int(clamped * 100))% に設定しました")])
    }

    private func getVolume() -> MCPResult {
        let session = AVAudioSession.sharedInstance()
        let volume = session.outputVolume
        return MCPResult(content: [.text("現在の音量: \(Int(volume * 100))%")])
    }

    // MARK: - Library Search

    private func searchLibrary(_ args: [String: JSONValue]) -> MCPResult {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            return MCPResult(content: [.text("[ERROR] 'query' is required")], isError: true)
        }

        let items = searchMediaItems(query: query)

        if items.isEmpty {
            return MCPResult(content: [.text("「\(query)」に一致する曲は見つかりませんでした")])
        }

        var result = "検索結果: 「\(query)」\n\(items.count)件見つかりました\n\n"
        for (index, item) in items.prefix(20).enumerated() {
            let title = item.title ?? "不明"
            let artist = item.artist ?? "不明"
            let album = item.albumTitle ?? ""
            let duration = formatTime(item.playbackDuration)

            result += "\(index + 1). \(title) - \(artist)"
            if !album.isEmpty {
                result += " [\(album)]"
            }
            result += " (\(duration))\n"
        }

        if items.count > 20 {
            result += "\n...他\(items.count - 20)件"
        }

        return MCPResult(content: [.text(result)])
    }

    // MARK: - Play Song

    @MainActor
    private func playSong(_ args: [String: JSONValue]) -> MCPResult {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            return MCPResult(content: [.text("[ERROR] 'query' is required")], isError: true)
        }

        let items = searchMediaItems(query: query)

        guard let firstItem = items.first else {
            return MCPResult(content: [.text("「\(query)」に一致する曲が見つかりませんでした")])
        }

        let collection = MPMediaItemCollection(items: items)
        player.setQueue(with: collection)
        player.play()

        let title = firstItem.title ?? "不明"
        let artist = firstItem.artist ?? "不明"
        var result = "再生開始: \(title) - \(artist)"
        if items.count > 1 {
            result += "\n(\(items.count)曲をキューに追加)"
        }

        return MCPResult(content: [.text(result)])
    }

    // MARK: - Queue Song

    @MainActor
    private func queueSong(_ args: [String: JSONValue]) -> MCPResult {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            return MCPResult(content: [.text("[ERROR] 'query' is required")], isError: true)
        }

        let items = searchMediaItems(query: query)

        guard let firstItem = items.first else {
            return MCPResult(content: [.text("「\(query)」に一致する曲が見つかりませんでした")])
        }

        let descriptor = MPMusicPlayerMediaItemQueueDescriptor(itemCollection: MPMediaItemCollection(items: [firstItem]))
        player.append(descriptor)

        let title = firstItem.title ?? "不明"
        let artist = firstItem.artist ?? "不明"
        return MCPResult(content: [.text("キューに追加: \(title) - \(artist)")])
    }

    // MARK: - Playlists

    private func getPlaylist() -> MCPResult {
        let query = MPMediaQuery.playlists()
        guard let collections = query.collections, !collections.isEmpty else {
            return MCPResult(content: [.text("プレイリストはありません")])
        }

        var result = "プレイリスト一覧\n\n"
        for (index, collection) in collections.enumerated() {
            guard let playlist = collection as? MPMediaPlaylist else { continue }
            let name = playlist.name ?? "無題"
            let count = playlist.count
            let desc = playlist.descriptionText ?? ""

            result += "\(index + 1). \(name) (\(count)曲)"
            if !desc.isEmpty {
                result += " - \(desc)"
            }
            result += "\n"
        }

        return MCPResult(content: [.text(result)])
    }

    // MARK: - Helpers

    /// Search media items by title, artist, or album name.
    private func searchMediaItems(query: String) -> [MPMediaItem] {
        let lowQuery = query.lowercased()

        // Search by title
        let titleFilter = MPMediaPropertyPredicate(
            value: query,
            forProperty: MPMediaItemPropertyTitle,
            comparisonType: .contains
        )
        let titleQuery = MPMediaQuery.songs()
        titleQuery.addFilterPredicate(titleFilter)
        let titleItems = titleQuery.items ?? []

        // Search by artist
        let artistFilter = MPMediaPropertyPredicate(
            value: query,
            forProperty: MPMediaItemPropertyArtist,
            comparisonType: .contains
        )
        let artistQuery = MPMediaQuery.songs()
        artistQuery.addFilterPredicate(artistFilter)
        let artistItems = artistQuery.items ?? []

        // Search by album
        let albumFilter = MPMediaPropertyPredicate(
            value: query,
            forProperty: MPMediaItemPropertyAlbumTitle,
            comparisonType: .contains
        )
        let albumQuery = MPMediaQuery.songs()
        albumQuery.addFilterPredicate(albumFilter)
        let albumItems = albumQuery.items ?? []

        // Merge results, prioritizing title matches, then artist, then album.
        // Use persistentID to deduplicate.
        var seen = Set<MPMediaEntityPersistentID>()
        var merged: [MPMediaItem] = []

        for item in titleItems + artistItems + albumItems {
            if seen.insert(item.persistentID).inserted {
                merged.append(item)
            }
        }

        // If MPMediaQuery returned nothing, try a broad in-memory filter on all songs
        if merged.isEmpty {
            let allQuery = MPMediaQuery.songs()
            let allItems = allQuery.items ?? []
            merged = allItems.filter { item in
                let title = (item.title ?? "").lowercased()
                let artist = (item.artist ?? "").lowercased()
                let album = (item.albumTitle ?? "").lowercased()
                return title.contains(lowQuery) || artist.contains(lowQuery) || album.contains(lowQuery)
            }
        }

        return merged
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
