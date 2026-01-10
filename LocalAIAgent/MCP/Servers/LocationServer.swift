import Foundation
import CoreLocation

final class LocationServer: NSObject, MCPServer {
    let id = "location"
    let name = "位置情報"
    let serverDescription = "現在地の取得と場所の検索を行います"
    let icon = "location"

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "get_current_location",
                description: "現在地を取得します",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "geocode_address",
                description: "住所から座標を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "address": MCPPropertySchema(type: "string", description: "住所")
                    ],
                    required: ["address"]
                )
            ),
            MCPTool(
                name: "reverse_geocode",
                description: "座標から住所を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "latitude": MCPPropertySchema(type: "number", description: "緯度"),
                        "longitude": MCPPropertySchema(type: "number", description: "経度")
                    ],
                    required: ["latitude", "longitude"]
                )
            ),
            MCPTool(
                name: "calculate_distance",
                description: "2地点間の距離を計算します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "from_lat": MCPPropertySchema(type: "number", description: "出発地の緯度"),
                        "from_lng": MCPPropertySchema(type: "number", description: "出発地の経度"),
                        "to_lat": MCPPropertySchema(type: "number", description: "目的地の緯度"),
                        "to_lng": MCPPropertySchema(type: "number", description: "目的地の経度")
                    ],
                    required: ["from_lat", "from_lng", "to_lat", "to_lng"]
                )
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "get_current_location":
            return try await getCurrentLocation()
        case "geocode_address":
            return try await geocodeAddress(arguments: arguments)
        case "reverse_geocode":
            return try await reverseGeocode(arguments: arguments)
        case "calculate_distance":
            return try await calculateDistance(arguments: arguments)
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func requestAccess() async throws {
        let status = locationManager.authorizationStatus

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            try await Task.sleep(nanoseconds: 500_000_000)
            let newStatus = locationManager.authorizationStatus
            guard newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways else {
                throw MCPClientError.permissionDenied("位置情報へのアクセスが拒否されました")
            }
        default:
            throw MCPClientError.permissionDenied("位置情報へのアクセス権限がありません")
        }
    }

    private func getCurrentLocation() async throws -> MCPResult {
        try await requestAccess()

        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }

        var result = "📍 現在地\n\n"
        result += "緯度: \(location.coordinate.latitude)\n"
        result += "経度: \(location.coordinate.longitude)\n"
        result += "精度: \(Int(location.horizontalAccuracy))m\n"
        result += "高度: \(Int(location.altitude))m\n"

        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            result += "\n住所: \(formatPlacemark(placemark))\n"
        }

        return MCPResult(content: [.text(result)])
    }

    private func geocodeAddress(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let address = arguments["address"]?.stringValue else {
            throw MCPClientError.invalidArguments("address is required")
        }

        let placemarks = try await geocoder.geocodeAddressString(address)

        guard let placemark = placemarks.first, let location = placemark.location else {
            throw MCPClientError.executionFailed("住所が見つかりませんでした")
        }

        var result = "🔍 ジオコーディング結果\n\n"
        result += "検索: \(address)\n\n"
        result += "緯度: \(location.coordinate.latitude)\n"
        result += "経度: \(location.coordinate.longitude)\n"
        result += "住所: \(formatPlacemark(placemark))\n"

        return MCPResult(content: [.text(result)])
    }

    private func reverseGeocode(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let latValue = arguments["latitude"],
              let lngValue = arguments["longitude"] else {
            throw MCPClientError.invalidArguments("latitude and longitude are required")
        }

        let lat: Double
        let lng: Double

        switch latValue {
        case .double(let d): lat = d
        case .int(let i): lat = Double(i)
        default: throw MCPClientError.invalidArguments("Invalid latitude")
        }

        switch lngValue {
        case .double(let d): lng = d
        case .int(let i): lng = Double(i)
        default: throw MCPClientError.invalidArguments("Invalid longitude")
        }

        let location = CLLocation(latitude: lat, longitude: lng)
        let placemarks = try await geocoder.reverseGeocodeLocation(location)

        guard let placemark = placemarks.first else {
            throw MCPClientError.executionFailed("住所が見つかりませんでした")
        }

        var result = "🔍 逆ジオコーディング結果\n\n"
        result += "座標: (\(lat), \(lng))\n\n"
        result += "住所: \(formatPlacemark(placemark))\n"

        if let country = placemark.country {
            result += "国: \(country)\n"
        }

        if let postalCode = placemark.postalCode {
            result += "郵便番号: \(postalCode)\n"
        }

        return MCPResult(content: [.text(result)])
    }

    private func calculateDistance(arguments: [String: JSONValue]) async throws -> MCPResult {
        func extractDouble(_ value: JSONValue?) -> Double? {
            switch value {
            case .double(let d): return d
            case .int(let i): return Double(i)
            default: return nil
            }
        }

        guard let fromLat = extractDouble(arguments["from_lat"]),
              let fromLng = extractDouble(arguments["from_lng"]),
              let toLat = extractDouble(arguments["to_lat"]),
              let toLng = extractDouble(arguments["to_lng"]) else {
            throw MCPClientError.invalidArguments("All coordinates are required")
        }

        let from = CLLocation(latitude: fromLat, longitude: fromLng)
        let to = CLLocation(latitude: toLat, longitude: toLng)

        let distance = from.distance(from: to)

        var result = "📏 距離計算結果\n\n"
        result += "出発地: (\(fromLat), \(fromLng))\n"
        result += "目的地: (\(toLat), \(toLng))\n\n"

        if distance >= 1000 {
            result += "距離: \(String(format: "%.2f", distance / 1000)) km\n"
        } else {
            result += "距離: \(Int(distance)) m\n"
        }

        return MCPResult(content: [.text(result)])
    }

    private func formatPlacemark(_ placemark: CLPlacemark) -> String {
        var components: [String] = []

        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }

        if let locality = placemark.locality {
            components.append(locality)
        }

        if let subLocality = placemark.subLocality {
            components.append(subLocality)
        }

        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }

        if let subThoroughfare = placemark.subThoroughfare {
            components.append(subThoroughfare)
        }

        return components.joined(separator: " ")
    }
}

extension LocationServer: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}
