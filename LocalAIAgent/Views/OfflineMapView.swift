import SwiftUI
import MapKit

/// Offline Map View - Displays emergency shelters on map with route planning
struct OfflineMapView: View {
    @StateObject private var mapManager = OfflineMapManager.shared
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503), // Tokyo
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var selectedShelter: EmergencyShelter?
    @State private var showingFilters = false
    @State private var filterDisasterType: DisasterType?
    @State private var filterFacility: Facility?
    @State private var calculatedRoute: MKRoute?
    @State private var showingRouteError = false
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                // Map
                Map(coordinateRegion: $region, annotationItems: filteredShelters) { shelter in
                    MapAnnotation(coordinate: shelter.coordinate) {
                        ShelterAnnotation(shelter: shelter, isSelected: selectedShelter?.id == shelter.id)
                            .onTapGesture {
                                selectedShelter = shelter
                                withAnimation {
                                    region.center = shelter.coordinate
                                }
                            }
                    }
                }
                .ignoresSafeArea()

                // Search Bar
                VStack {
                    HStack {
                        SearchBar(text: $searchText)
                            .padding(.horizontal)

                        Button(action: { showingFilters.toggle() }) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .padding(.trailing)
                        }
                    }
                    .padding(.top)
                    .background(.regularMaterial)

                    Spacer()
                }

                // Shelter Info Card
                if let shelter = selectedShelter {
                    ShelterInfoCard(
                        shelter: shelter,
                        userLocation: mapManager.userLocation,
                        onNavigate: {
                            navigateToShelter(shelter)
                        },
                        onClose: {
                            selectedShelter = nil
                            calculatedRoute = nil
                        }
                    )
                    .transition(.move(edge: .bottom))
                }

                // Nearest Shelter Button
                if selectedShelter == nil, let nearest = mapManager.nearestShelter {
                    VStack {
                        Spacer()
                        Button(action: {
                            selectedShelter = nearest
                            withAnimation {
                                region.center = nearest.coordinate
                            }
                        }) {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                Text("最寄りの避難所")
                                if let location = mapManager.userLocation {
                                    Text("・\(mapManager.formattedDistance(from: location, to: nearest))")
                                        .font(.caption)
                                }
                            }
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("避難所マップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: centerOnUserLocation) {
                        Image(systemName: "location")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterView(
                    disasterType: $filterDisasterType,
                    facility: $filterFacility
                )
            }
            .alert("ルート計算エラー", isPresented: $showingRouteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("ルートを計算できませんでした")
            }
            .onAppear {
                mapManager.requestLocationAuthorization()
                mapManager.startUpdatingLocation()
            }
            .onDisappear {
                mapManager.stopUpdatingLocation()
            }
        }
    }

    private var filteredShelters: [EmergencyShelter] {
        var shelters = mapManager.shelters

        // Search filter
        if !searchText.isEmpty {
            shelters = mapManager.searchShelters(query: searchText)
        }

        // Disaster type filter
        if let type = filterDisasterType {
            shelters = shelters.filter { $0.disasterTypes.contains(type) }
        }

        // Facility filter
        if let facility = filterFacility {
            shelters = shelters.filter { $0.facilities.contains(facility) }
        }

        return shelters
    }

    private func centerOnUserLocation() {
        guard let location = mapManager.userLocation else { return }
        withAnimation {
            region.center = location.coordinate
        }
    }

    private func navigateToShelter(_ shelter: EmergencyShelter) {
        guard let userLocation = mapManager.userLocation else {
            showingRouteError = true
            return
        }

        Task {
            do {
                let route = try await mapManager.calculateRoute(from: userLocation, to: shelter)
                calculatedRoute = route
                // Note: Displaying route on map requires custom MKMapView
                // For now, we can open in Apple Maps
                openInAppleMaps(shelter)
            } catch {
                showingRouteError = true
            }
        }
    }

    private func openInAppleMaps(_ shelter: EmergencyShelter) {
        let placemark = MKPlacemark(coordinate: shelter.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = shelter.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}

// MARK: - Shelter Annotation

struct ShelterAnnotation: View {
    let shelter: EmergencyShelter
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "house.fill")
                .font(.system(size: isSelected ? 28 : 20))
                .foregroundStyle(isSelected ? .red : .blue)
                .background(
                    Circle()
                        .fill(.white)
                        .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                )

            if isSelected {
                Text(shelter.name)
                    .font(.caption)
                    .padding(4)
                    .background(.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .animation(.spring(), value: isSelected)
    }
}

// MARK: - Shelter Info Card

struct ShelterInfoCard: View {
    let shelter: EmergencyShelter
    let userLocation: CLLocation?
    let onNavigate: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(shelter.name)
                        .font(.headline)

                    if let location = userLocation {
                        let distance = OfflineMapManager.shared.formattedDistance(from: location, to: shelter)
                        Text("\(distance) • 収容人数: \(shelter.capacity)人")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(shelter.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Disaster types
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(shelter.disasterTypes, id: \.self) { type in
                        HStack(spacing: 4) {
                            Image(systemName: type.icon)
                            Text(type.displayName)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            // Facilities
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                ForEach(shelter.facilities.prefix(6), id: \.self) { facility in
                    HStack(spacing: 4) {
                        Image(systemName: facility.icon)
                        Text(facility.displayName)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            // Tags
            HStack {
                if shelter.barrierFree {
                    TagView(text: "バリアフリー", icon: "figure.roll")
                }
                if shelter.petAllowed {
                    TagView(text: "ペット可", icon: "pawprint")
                }
            }

            // Navigate button
            Button(action: onNavigate) {
                HStack {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    Text("経路を表示")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let notes = shelter.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .padding()
    }
}

struct TagView: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .foregroundStyle(.green)
        .clipShape(Capsule())
    }
}

// MARK: - Filter View

struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var disasterType: DisasterType?
    @Binding var facility: Facility?

    var body: some View {
        NavigationView {
            Form {
                Section("災害種別") {
                    Picker("災害種別", selection: $disasterType) {
                        Text("すべて").tag(nil as DisasterType?)
                        ForEach(DisasterType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type as DisasterType?)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("設備") {
                    Picker("設備", selection: $facility) {
                        Text("すべて").tag(nil as Facility?)
                        ForEach(Facility.allCases, id: \.self) { fac in
                            HStack {
                                Image(systemName: fac.icon)
                                Text(fac.displayName)
                            }
                            .tag(fac as Facility?)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("フィルター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("リセット") {
                        disasterType = nil
                        facility = nil
                    }
                }
            }
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("避難所を検索", text: $text)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    OfflineMapView()
}
