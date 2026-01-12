import Foundation
import CoreLocation
import WeatherKit

/// MCP Server for Weather - Get weather information using Apple WeatherKit (no API key required)
final class WeatherServer: NSObject, MCPServer {
    let id = "weather"
    let name = "天気"
    let serverDescription = "天気予報を取得します（Apple WeatherKit使用）"
    let icon = "cloud.sun"

    private let weatherService = WeatherService.shared
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "get_current_weather",
                description: "現在の天気を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "location": MCPPropertySchema(type: "string", description: "場所の名前（省略時は現在地）")
                    ],
                    required: []
                )
            ),
            MCPTool(
                name: "get_forecast",
                description: "天気予報を取得します（最大10日間）",
                inputSchema: MCPInputSchema(
                    properties: [
                        "location": MCPPropertySchema(type: "string", description: "場所の名前（省略時は現在地）"),
                        "days": MCPPropertySchema(type: "integer", description: "予報日数（デフォルト: 3、最大: 10）")
                    ],
                    required: []
                )
            ),
            MCPTool(
                name: "get_hourly_forecast",
                description: "時間ごとの天気予報を取得します（24時間）",
                inputSchema: MCPInputSchema(
                    properties: [
                        "location": MCPPropertySchema(type: "string", description: "場所の名前（省略時は現在地）")
                    ],
                    required: []
                )
            )
        ]
    }

    func listPrompts() -> [MCPPrompt] {
        [
            MCPPrompt(
                name: "weather_check",
                description: "今日の天気を確認します",
                descriptionEn: "Check today's weather",
                arguments: [
                    MCPPromptArgument(name: "location", description: "場所", descriptionEn: "Location", required: false)
                ]
            ),
            MCPPrompt(
                name: "weekly_weather",
                description: "週間天気予報を取得します",
                descriptionEn: "Get weekly weather forecast",
                arguments: [
                    MCPPromptArgument(name: "location", description: "場所", descriptionEn: "Location", required: false)
                ]
            )
        ]
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        switch name {
        case "weather_check":
            let location = arguments["location"] ?? "現在地"
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("\(location)の今日の天気を教えてください。"))
            ])
        case "weekly_weather":
            let location = arguments["location"] ?? "現在地"
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("\(location)の週間天気予報を教えてください。"))
            ])
        default:
            return nil
        }
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "get_current_weather":
            return try await getCurrentWeather(arguments: arguments)
        case "get_forecast":
            return try await getForecast(arguments: arguments)
        case "get_hourly_forecast":
            return try await getHourlyForecast(arguments: arguments)
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    // MARK: - Private Methods

    private func getLocation(from arguments: [String: JSONValue]) async throws -> CLLocation {
        if let locationName = arguments["location"]?.stringValue, !locationName.isEmpty {
            // Geocode the location name
            let placemarks = try await geocoder.geocodeAddressString(locationName)
            guard let placemark = placemarks.first, let location = placemark.location else {
                throw MCPClientError.executionFailed("場所「\(locationName)」が見つかりませんでした")
            }
            return location
        } else {
            // Use current location
            return try await getCurrentDeviceLocation()
        }
    }

    private func getCurrentDeviceLocation() async throws -> CLLocation {
        try await requestLocationAccess()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    private func requestLocationAccess() async throws {
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
            throw MCPClientError.permissionDenied("位置情報へのアクセス権限がありません。天気情報を取得するには場所を指定してください。")
        }
    }

    private func getLocationName(for location: CLLocation) async -> String {
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            var components: [String] = []
            if let locality = placemark.locality {
                components.append(locality)
            }
            if let administrativeArea = placemark.administrativeArea {
                components.append(administrativeArea)
            }
            return components.isEmpty ? "現在地" : components.joined(separator: ", ")
        }
        return "現在地"
    }

    private func getCurrentWeather(arguments: [String: JSONValue]) async throws -> MCPResult {
        let location = try await getLocation(from: arguments)
        let locationName = await getLocationName(for: location)

        let weather = try await weatherService.weather(for: location)
        let current = weather.currentWeather

        var result = "🌤️ \(locationName)の現在の天気\n\n"
        result += "状況: \(current.condition.description)\n"
        result += "気温: \(formatTemperature(current.temperature.value))°C\n"
        result += "体感温度: \(formatTemperature(current.apparentTemperature.value))°C\n"
        result += "湿度: \(Int(current.humidity * 100))%\n"
        result += "風速: \(String(format: "%.1f", current.wind.speed.value)) km/h (\(current.wind.compassDirection.description))\n"
        result += "UV指数: \(current.uvIndex.value) (\(uvIndexDescription(current.uvIndex.value)))\n"
        result += "気圧: \(Int(current.pressure.value)) hPa\n"
        result += "視程: \(String(format: "%.1f", current.visibility.value / 1000)) km\n"

        return MCPResult(content: [.text(result)])
    }

    private func getForecast(arguments: [String: JSONValue]) async throws -> MCPResult {
        let location = try await getLocation(from: arguments)
        let locationName = await getLocationName(for: location)

        var days = 3
        if case .int(let d) = arguments["days"] {
            days = min(max(d, 1), 10)
        }

        let weather = try await weatherService.weather(for: location)

        var result = "📅 \(locationName)の\(days)日間の天気予報\n\n"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "M/d (E)"

        for (index, day) in weather.dailyForecast.prefix(days).enumerated() {
            let dateStr = dateFormatter.string(from: day.date)
            let icon = weatherIcon(for: day.condition)

            result += "\(icon) \(dateStr)\n"
            result += "  天気: \(day.condition.description)\n"
            result += "  最高: \(formatTemperature(day.highTemperature.value))°C / 最低: \(formatTemperature(day.lowTemperature.value))°C\n"
            result += "  降水確率: \(Int(day.precipitationChance * 100))%\n"
            if day.precipitationAmount.value > 0 {
                result += "  降水量: \(String(format: "%.1f", day.precipitationAmount.value)) mm\n"
            }
            result += "  UV指数: \(day.uvIndex.value)\n"
            if index < days - 1 {
                result += "\n"
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func getHourlyForecast(arguments: [String: JSONValue]) async throws -> MCPResult {
        let location = try await getLocation(from: arguments)
        let locationName = await getLocationName(for: location)

        let weather = try await weatherService.weather(for: location)

        var result = "🕐 \(locationName)の24時間予報\n\n"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ja_JP")
        timeFormatter.dateFormat = "H時"

        for hour in weather.hourlyForecast.prefix(24) {
            let timeStr = timeFormatter.string(from: hour.date)
            let icon = weatherIcon(for: hour.condition)
            let temp = formatTemperature(hour.temperature.value)
            let rain = Int(hour.precipitationChance * 100)

            result += "\(timeStr): \(icon) \(temp)°C (降水\(rain)%)\n"
        }

        return MCPResult(content: [.text(result)])
    }

    // MARK: - Helper Methods

    private func formatTemperature(_ celsius: Double) -> String {
        return String(format: "%.1f", celsius)
    }

    private func uvIndexDescription(_ index: Int) -> String {
        switch index {
        case 0...2: return "弱い"
        case 3...5: return "中程度"
        case 6...7: return "強い"
        case 8...10: return "非常に強い"
        default: return "極端に強い"
        }
    }

    private func weatherIcon(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return "☀️"
        case .mostlyClear: return "🌤️"
        case .partlyCloudy: return "⛅"
        case .mostlyCloudy: return "🌥️"
        case .cloudy: return "☁️"
        case .foggy, .haze: return "🌫️"
        case .drizzle, .rain: return "🌧️"
        case .heavyRain: return "⛈️"
        case .snow, .heavySnow: return "❄️"
        case .sleet, .freezingRain: return "🌨️"
        case .thunderstorms: return "⛈️"
        case .windy, .breezy: return "💨"
        case .hot: return "🔥"
        case .frigid: return "🥶"
        default: return "🌡️"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherServer: CLLocationManagerDelegate {
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
