import Foundation
import Photos
import UIKit

final class PhotosServer: MCPServer {
    let id = "photos"
    let name = "写真"
    let serverDescription = "写真ライブラリにアクセスします"
    let icon = "photo"

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "list_albums",
                description: "アルバム一覧を取得します",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "get_recent_photos",
                description: "最近の写真を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "limit": MCPPropertySchema(type: "integer", description: "取得枚数（デフォルト: 10）")
                    ]
                )
            ),
            MCPTool(
                name: "search_photos",
                description: "写真を検索します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "start_date": MCPPropertySchema(type: "string", description: "開始日 (YYYY-MM-DD)"),
                        "end_date": MCPPropertySchema(type: "string", description: "終了日 (YYYY-MM-DD)"),
                        "media_type": MCPPropertySchema(
                            type: "string",
                            description: "メディアタイプ",
                            enumValues: ["photo", "video", "all"]
                        ),
                        "limit": MCPPropertySchema(type: "integer", description: "取得枚数")
                    ]
                )
            ),
            MCPTool(
                name: "get_photo_info",
                description: "写真の詳細情報を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "asset_id": MCPPropertySchema(type: "string", description: "写真のID")
                    ],
                    required: ["asset_id"]
                )
            ),
            MCPTool(
                name: "get_photos_stats",
                description: "写真ライブラリの統計情報を取得します",
                inputSchema: MCPInputSchema()
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        try await requestAccess()

        switch name {
        case "list_albums":
            return try await listAlbums()
        case "get_recent_photos":
            return try await getRecentPhotos(arguments: arguments)
        case "search_photos":
            return try await searchPhotos(arguments: arguments)
        case "get_photo_info":
            return try await getPhotoInfo(arguments: arguments)
        case "get_photos_stats":
            return try await getPhotosStats()
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func requestAccess() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard newStatus == .authorized || newStatus == .limited else {
                throw MCPClientError.permissionDenied("写真ライブラリへのアクセスが拒否されました")
            }
        default:
            throw MCPClientError.permissionDenied("写真ライブラリへのアクセス権限がありません")
        }
    }

    private func listAlbums() async throws -> MCPResult {
        var result = "📸 アルバム一覧\n\n"

        // Smart Albums
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )

        result += "### スマートアルバム\n"
        smartAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            if count > 0 {
                result += "• \(collection.localizedTitle ?? "無題") (\(count))\n"
            }
        }

        // User Albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        if userAlbums.count > 0 {
            result += "\n### ユーザーアルバム\n"
            userAlbums.enumerateObjects { collection, _, _ in
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                result += "• \(collection.localizedTitle ?? "無題") (\(count))\n"
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func getRecentPhotos(arguments: [String: JSONValue]) async throws -> MCPResult {
        let limit = arguments["limit"]?.intValue ?? 10

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var result = "📷 最近の写真 (\(assets.count)枚)\n\n"

        assets.enumerateObjects { asset, index, _ in
            result += self.formatAssetSummary(asset, index: index + 1)
        }

        return MCPResult(content: [.text(result)])
    }

    private func searchPhotos(arguments: [String: JSONValue]) async throws -> MCPResult {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var predicates: [NSPredicate] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        if let startDateStr = arguments["start_date"]?.stringValue,
           let startDate = dateFormatter.date(from: startDateStr) {
            predicates.append(NSPredicate(format: "creationDate >= %@", startDate as NSDate))
        }

        if let endDateStr = arguments["end_date"]?.stringValue,
           let endDate = dateFormatter.date(from: endDateStr) {
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: endDate)!
            predicates.append(NSPredicate(format: "creationDate < %@", nextDay as NSDate))
        }

        let mediaType = arguments["media_type"]?.stringValue ?? "all"
        switch mediaType {
        case "photo":
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        case "video":
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        default:
            break
        }

        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        options.fetchLimit = arguments["limit"]?.intValue ?? 20

        let assets = PHAsset.fetchAssets(with: options)

        var result = "🔍 検索結果 (\(assets.count)件)\n\n"

        assets.enumerateObjects { asset, index, _ in
            result += self.formatAssetSummary(asset, index: index + 1)
        }

        return MCPResult(content: [.text(result)])
    }

    private func getPhotoInfo(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let assetId = arguments["asset_id"]?.stringValue else {
            throw MCPClientError.invalidArguments("asset_id is required")
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = assets.firstObject else {
            throw MCPClientError.executionFailed("写真が見つかりません")
        }

        var result = "📷 写真詳細\n\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年M月d日 HH:mm"

        if let creationDate = asset.creationDate {
            result += "撮影日時: \(dateFormatter.string(from: creationDate))\n"
        }

        result += "サイズ: \(asset.pixelWidth) x \(asset.pixelHeight)\n"

        if let location = asset.location {
            result += "位置: \(location.coordinate.latitude), \(location.coordinate.longitude)\n"
        }

        result += "メディアタイプ: \(mediaTypeString(asset.mediaType))\n"

        if asset.mediaType == .video {
            let duration = Int(asset.duration)
            result += "長さ: \(duration / 60)分\(duration % 60)秒\n"
        }

        result += "お気に入り: \(asset.isFavorite ? "はい" : "いいえ")\n"
        result += "ID: \(asset.localIdentifier)\n"

        return MCPResult(content: [.text(result)])
    }

    private func getPhotosStats() async throws -> MCPResult {
        var result = "📊 写真ライブラリ統計\n\n"

        let photoOptions = PHFetchOptions()
        photoOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let photos = PHAsset.fetchAssets(with: photoOptions)

        let videoOptions = PHFetchOptions()
        videoOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let videos = PHAsset.fetchAssets(with: videoOptions)

        result += "写真: \(photos.count)枚\n"
        result += "動画: \(videos.count)本\n"

        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        result += "アルバム: \(albums.count)個\n"

        let favoriteOptions = PHFetchOptions()
        favoriteOptions.predicate = NSPredicate(format: "isFavorite == YES")
        let favorites = PHAsset.fetchAssets(with: favoriteOptions)
        result += "お気に入り: \(favorites.count)件\n"

        return MCPResult(content: [.text(result)])
    }

    private func formatAssetSummary(_ asset: PHAsset, index: Int) -> String {
        var str = "\(index). "

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d HH:mm"

        if let date = asset.creationDate {
            str += "\(dateFormatter.string(from: date)) "
        }

        str += mediaTypeEmoji(asset.mediaType)
        str += " \(asset.pixelWidth)x\(asset.pixelHeight)"

        if asset.isFavorite {
            str += " ❤️"
        }

        str += "\n   ID: \(asset.localIdentifier)\n\n"
        return str
    }

    private func mediaTypeString(_ type: PHAssetMediaType) -> String {
        switch type {
        case .image: return "写真"
        case .video: return "動画"
        case .audio: return "オーディオ"
        default: return "不明"
        }
    }

    private func mediaTypeEmoji(_ type: PHAssetMediaType) -> String {
        switch type {
        case .image: return "🖼️"
        case .video: return "🎬"
        case .audio: return "🎵"
        default: return "📄"
        }
    }
}
