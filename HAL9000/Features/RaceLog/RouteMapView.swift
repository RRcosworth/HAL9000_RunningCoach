import MapKit
import SwiftUI

struct RouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let fallbackCoordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition

    init(coordinates: [CLLocationCoordinate2D], fallbackCoordinate: CLLocationCoordinate2D? = nil) {
        self.coordinates = coordinates
        self.fallbackCoordinate = fallbackCoordinate
        _position = State(initialValue: .region(Self.region(for: coordinates, fallbackCoordinate: fallbackCoordinate)))
    }

    var body: some View {
        Map(position: $position) {
            if !coordinates.isEmpty {
                MapPolyline(coordinates: coordinates)
                    .stroke(AppColor.accent, lineWidth: 4)

                if let start = coordinates.first {
                    Marker("Start", systemImage: "play.fill", coordinate: start)
                        .tint(.green)
                }

                if let end = coordinates.last {
                    Marker("Finish", systemImage: "flag.checkered", coordinate: end)
                        .tint(.red)
                }
            } else if let fallbackCoordinate {
                Marker("Race", systemImage: "flag.checkered", coordinate: fallbackCoordinate)
                    .tint(AppColor.accent)
            }
        }
        .mapControlVisibility(.hidden)
        .onChange(of: coordinates.count) { _, _ in
            position = .region(Self.region(for: coordinates, fallbackCoordinate: fallbackCoordinate))
        }
    }

    private static func region(for coordinates: [CLLocationCoordinate2D], fallbackCoordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            if let fallbackCoordinate {
                return MKCoordinateRegion(
                    center: fallbackCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                )
            }

            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
                span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
            )
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.35, 0.01)
        let lonDelta = max((maxLon - minLon) * 1.35, 0.01)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
