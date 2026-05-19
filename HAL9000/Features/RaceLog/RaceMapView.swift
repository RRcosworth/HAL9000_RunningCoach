import MapKit
import SwiftUI

struct RaceMapView: View {
    let races: [RaceActivity]
    @State private var position: MapCameraPosition

    init(races: [RaceActivity]) {
        self.races = races
        _position = State(initialValue: .region(Self.region(for: races)))
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
        .onChange(of: races) { _, newValue in
            position = .region(Self.region(for: newValue))
        }
    }

    private static func region(for races: [RaceActivity]) -> MKCoordinateRegion {
        let coordinates = races.compactMap(\.coordinate)
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
                span: MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 65)
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
