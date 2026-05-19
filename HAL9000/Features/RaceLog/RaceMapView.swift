import MapKit
import SwiftUI

struct RaceMapView: View {
    let races: [RaceActivity]
    @StateObject private var locationProvider = RaceMapLocationProvider()
    @State private var position: MapCameraPosition

    init(races: [RaceActivity]) {
        self.races = races
        _position = State(initialValue: .region(Self.region(for: races, fallbackCoordinate: nil)))
    }

    var body: some View {
        Map(position: $position) {
            ForEach(races) { race in
                if let coordinate = race.coordinate {
                    Marker(race.name, systemImage: "flag.checkered", coordinate: coordinate)
                        .tint(AppColor.accent)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .task {
            if races.compactMap(\.coordinate).isEmpty {
                locationProvider.requestLocationIfNeeded()
            }
        }
        .onChange(of: races) { _, newValue in
            let fallback = locationProvider.coordinate
            position = .region(Self.region(for: newValue, fallbackCoordinate: fallback))
            if newValue.compactMap(\.coordinate).isEmpty {
                locationProvider.requestLocationIfNeeded()
            }
        }
        .onChange(of: locationProvider.updateID) { _, _ in
            guard races.compactMap(\.coordinate).isEmpty else { return }
            let coordinate = locationProvider.coordinate
            position = .region(Self.region(for: races, fallbackCoordinate: coordinate))
        }
    }

    private static func region(for races: [RaceActivity], fallbackCoordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        let coordinates = races.compactMap(\.coordinate)
        guard !coordinates.isEmpty else {
            if let fallbackCoordinate {
                return MKCoordinateRegion(
                    center: fallbackCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                )
            }

            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 180)
            )
        }

        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
            )
        }

        let minLat = coordinates.map(\.latitude).min() ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? 0
        let minLon = coordinates.map(\.longitude).min() ?? 0
        let maxLon = coordinates.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.2),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.2)
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}
