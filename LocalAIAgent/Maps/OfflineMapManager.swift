import Foundation
import MapKit
import CoreLocation

/// Offline Map Manager - Manages offline maps and emergency shelter database
/// Provides shelter search, route calculation, and map tile caching
@MainActor
final class OfflineMapManager: NSObject, ObservableObject {
    static let shared = OfflineMapManager()

    // MARK: - Published Properties

    @Published var shelters: [EmergencyShelter] = []
    @Published var downloadedRegions: [MapRegion] = []
    @Published var nearestShelter: EmergencyShelter?
    @Published var userLocation: CLLocation?

    // MARK: - Private Properties

    private var sheltersDB: [String: Any] = [:]
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    // MARK: - Initialization

    override private init() {
        super.init()
        setupLocationManager()
        loadSheltersDB()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func loadSheltersDB() {
        guard let url = Bundle.main.url(forResource: "EmergencySheltersDB", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[OfflineMapManager] Failed to load shelters database")
            return
        }

        sheltersDB = json
        parseShelters()
    }

    private func parseShelters() {
        guard let regions = sheltersDB["regions"] as? [String: Any] else { return }

        var allShelters: [EmergencyShelter] = []

        for (_, regionValue) in regions {
            guard let region = regionValue as? [String: Any],
                  let municipalities = region["municipalities"] as? [String: Any] else { continue }

            for (_, municipalityValue) in municipalities {
                guard let municipality = municipalityValue as? [String: Any],
                      let sheltersList = municipality["shelters"] as? [[String: Any]] else { continue }

                for shelterData in sheltersList {
                    if let shelter = parseShelter(from: shelterData) {
                        allShelters.append(shelter)
                    }
                }
            }
        }

        shelters = allShelters
    }

    private func parseShelter(from data: [String: Any]) -> EmergencyShelter? {
        guard let id = data["id"] as? String,
              let name = data["name"] as? String,
              let address = data["address"] as? String,
              let lat = data["lat"] as? Double,
              let lon = data["lon"] as? Double,
              let capacity = data["capacity"] as? Int else {
            return nil
        }

        let typeStrings = data["type"] as? [String] ?? []
        let disasterTypes = typeStrings.compactMap { DisasterType(rawValue: $0) }

        let facilityStrings = data["facilities"] as? [String] ?? []
        let facilities = facilityStrings.compactMap { Facility(rawValue: $0) }

        return EmergencyShelter(
            id: id,
            name: name,
            address: address,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            capacity: capacity,
            disasterTypes: disasterTypes,
            facilities: facilities,
            barrierFree: data["barrier_free"] as? Bool ?? false,
            petAllowed: data["pet_allowed"] as? Bool ?? false,
            contact: data["contact"] as? String,
            notes: data["notes"] as? String
        )
    }

    // MARK: - Location Services

    func requestLocationAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - Shelter Search

    /// Find nearest shelter from current location
    func findNearestShelter(from location: CLLocation? = nil) -> EmergencyShelter? {
        guard let location = location ?? userLocation else { return nil }

        let sortedByDistance = shelters.sorted { shelter1, shelter2 in
            let distance1 = location.distance(from: CLLocation(
                latitude: shelter1.coordinate.latitude,
                longitude: shelter1.coordinate.longitude
            ))
            let distance2 = location.distance(from: CLLocation(
                latitude: shelter2.coordinate.latitude,
                longitude: shelter2.coordinate.longitude
            ))
            return distance1 < distance2
        }

        nearestShelter = sortedByDistance.first
        return nearestShelter
    }

    /// Find shelters within radius (meters)
    func findSheltersNearby(location: CLLocation, radiusMeters: Double = 5000) -> [EmergencyShelter] {
        return shelters.filter { shelter in
            let shelterLocation = CLLocation(
                latitude: shelter.coordinate.latitude,
                longitude: shelter.coordinate.longitude
            )
            let distance = location.distance(from: shelterLocation)
            return distance <= radiusMeters
        }.sorted { shelter1, shelter2 in
            let distance1 = location.distance(from: CLLocation(
                latitude: shelter1.coordinate.latitude,
                longitude: shelter1.coordinate.longitude
            ))
            let distance2 = location.distance(from: CLLocation(
                latitude: shelter2.coordinate.latitude,
                longitude: shelter2.coordinate.longitude
            ))
            return distance1 < distance2
        }
    }

    /// Search shelters by disaster type
    func findShelters(forDisasterType type: DisasterType) -> [EmergencyShelter] {
        return shelters.filter { $0.disasterTypes.contains(type) }
    }

    /// Search shelters by facility
    func findShelters(withFacility facility: Facility) -> [EmergencyShelter] {
        return shelters.filter { $0.facilities.contains(facility) }
    }

    /// Search shelters by name or address
    func searchShelters(query: String) -> [EmergencyShelter] {
        let lowercaseQuery = query.lowercased()
        return shelters.filter {
            $0.name.lowercased().contains(lowercaseQuery) ||
            $0.address.lowercased().contains(lowercaseQuery)
        }
    }

    // MARK: - Distance Calculation

    func distance(from location: CLLocation, to shelter: EmergencyShelter) -> CLLocationDistance {
        let shelterLocation = CLLocation(
            latitude: shelter.coordinate.latitude,
            longitude: shelter.coordinate.longitude
        )
        return location.distance(from: shelterLocation)
    }

    func formattedDistance(from location: CLLocation, to shelter: EmergencyShelter) -> String {
        let distance = self.distance(from: location, to: shelter)

        if distance < 1000 {
            return String(format: "%.0fm", distance)
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }

    // MARK: - Map Tile Management (Placeholder for future implementation)

    /// Download map tiles for offline use
    /// Note: This is a placeholder. Real implementation requires MapLibre or Mapbox SDK
    func downloadMapTiles(region: MapRegion) async throws {
        // TODO: Implement with MapLibre or Mapbox
        print("[OfflineMapManager] Map tile download not yet implemented")
        downloadedRegions.append(region)
    }

    /// Check if map tiles are available for region
    func hasOfflineMap(for region: MapRegion) -> Bool {
        return downloadedRegions.contains { $0.id == region.id }
    }

    // MARK: - Route Calculation

    /// Calculate route to shelter
    func calculateRoute(from source: CLLocation, to shelter: EmergencyShelter) async throws -> MKRoute {
        let sourcePlacemark = MKPlacemark(coordinate: source.coordinate)
        let destinationPlacemark = MKPlacemark(coordinate: shelter.coordinate)

        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        let destinationItem = MKMapItem(placemark: destinationPlacemark)

        let request = MKDirections.Request()
        request.source = sourceItem
        request.destination = destinationItem
        request.transportType = .walking  // Walking is most reliable in disasters

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let route = response.routes.first else {
            throw OfflineMapError.routeNotFound
        }

        return route
    }
}

// MARK: - CLLocationManagerDelegate

extension OfflineMapManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            self.userLocation = location
            _ = self.findNearestShelter(from: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[OfflineMapManager] Location error: \(error)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdatingLocation()
            case .denied, .restricted:
                print("[OfflineMapManager] Location permission denied")
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Supporting Types

struct EmergencyShelter: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let capacity: Int
    let disasterTypes: [DisasterType]
    let facilities: [Facility]
    let barrierFree: Bool
    let petAllowed: Bool
    let contact: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, address, capacity, disasterTypes, facilities
        case barrierFree, petAllowed, contact, notes
        case latitude, longitude
    }

    init(id: String, name: String, address: String, coordinate: CLLocationCoordinate2D,
         capacity: Int, disasterTypes: [DisasterType], facilities: [Facility],
         barrierFree: Bool, petAllowed: Bool, contact: String?, notes: String?) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.capacity = capacity
        self.disasterTypes = disasterTypes
        self.facilities = facilities
        self.barrierFree = barrierFree
        self.petAllowed = petAllowed
        self.contact = contact
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        capacity = try container.decode(Int.self, forKey: .capacity)
        disasterTypes = try container.decode([DisasterType].self, forKey: .disasterTypes)
        facilities = try container.decode([Facility].self, forKey: .facilities)
        barrierFree = try container.decode(Bool.self, forKey: .barrierFree)
        petAllowed = try container.decode(Bool.self, forKey: .petAllowed)
        contact = try container.decodeIfPresent(String.self, forKey: .contact)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(disasterTypes, forKey: .disasterTypes)
        try container.encode(facilities, forKey: .facilities)
        try container.encode(barrierFree, forKey: .barrierFree)
        try container.encode(petAllowed, forKey: .petAllowed)
        try container.encodeIfPresent(contact, forKey: .contact)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }

    static func == (lhs: EmergencyShelter, rhs: EmergencyShelter) -> Bool {
        lhs.id == rhs.id
    }
}

enum DisasterType: String, Codable, CaseIterable {
    case earthquake
    case tsunami
    case typhoon
    case flood
    case fire
    case landslide

    var displayName: String {
        switch self {
        case .earthquake: return "地震"
        case .tsunami: return "津波"
        case .typhoon: return "台風"
        case .flood: return "洪水"
        case .fire: return "火災"
        case .landslide: return "土砂災害"
        }
    }

    var icon: String {
        switch self {
        case .earthquake: return "waveform.path.ecg"
        case .tsunami: return "water.waves"
        case .typhoon: return "tornado"
        case .flood: return "cloud.heavyrain"
        case .fire: return "flame"
        case .landslide: return "mountain.2"
        }
    }
}

enum Facility: String, Codable, CaseIterable {
    case water, food, toilet, generator, medical
    case cooling, heating, shower, wifi, phoneCharger

    var displayName: String {
        switch self {
        case .water: return "飲料水"
        case .food: return "食料"
        case .toilet: return "トイレ"
        case .generator: return "発電機"
        case .medical: return "医療"
        case .cooling: return "冷房"
        case .heating: return "暖房"
        case .shower: return "シャワー"
        case .wifi: return "Wi-Fi"
        case .phoneCharger: return "充電"
        }
    }

    var icon: String {
        switch self {
        case .water: return "drop"
        case .food: return "fork.knife"
        case .toilet: return "toilet"
        case .generator: return "bolt"
        case .medical: return "cross.case"
        case .cooling: return "snowflake"
        case .heating: return "flame"
        case .shower: return "shower"
        case .wifi: return "wifi"
        case .phoneCharger: return "battery.100.bolt"
        }
    }
}

struct MapRegion: Identifiable, Codable {
    let id: String
    let name: String
    let centerLatitude: Double
    let centerLongitude: Double
    let spanLatitude: Double
    let spanLongitude: Double
}

enum OfflineMapError: Error, LocalizedError {
    case routeNotFound
    case locationUnavailable
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .routeNotFound:
            return "ルートが見つかりませんでした"
        case .locationUnavailable:
            return "位置情報が取得できません"
        case .downloadFailed:
            return "地図のダウンロードに失敗しました"
        }
    }
}
