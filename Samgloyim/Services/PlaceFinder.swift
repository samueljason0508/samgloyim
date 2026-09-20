import CoreLocation
import Foundation
import MapKit

struct NearbyPlace: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var category: SpendingCategory
    var metresAway: Int
}

/// Finds the shop you are standing in. There is no merchant database to build or host: MapKit
/// already knows where every business is, and its point-of-interest categories map onto the ones
/// this app already spends in.
///
/// Split the way `ReceiptScanner` is — the part that talks to the OS is one `async throws` call, and
/// the part worth testing is a pure function.
enum PlaceFinder {
    /// Wide enough to find the building you are inside, tight enough not to offer the mall next door.
    static let searchRadius: CLLocationDistance = 150

    static func nearbyPlaces() async throws -> [NearbyPlace] {
        let here = try await fix()
        let request = MKLocalPointsOfInterestRequest(center: here.coordinate, radius: searchRadius)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let name = item.name, let poi = item.pointOfInterestCategory,
                  let category = category(for: poi), let location = item.placemark.location else { return nil }
            return NearbyPlace(name: name, category: category, metresAway: Int(here.distance(from: location).rounded()))
        }.sorted { $0.metresAway < $1.metresAway }
    }

    /// A first fix often fails while the radio is still warming up — indoors, or on a simulator with
    /// no location set yet — and CoreLocation reports that as `locationUnknown`. It is worth one
    /// more try before telling the user anything, and the raw error is never worth showing them.
    private static func fix() async throws -> CLLocation {
        do {
            return try await LocationReading.current()
        } catch let error as CLError where error.code == .locationUnknown {
            try? await Task.sleep(for: .seconds(2))
            do {
                return try await LocationReading.current()
            } catch {
                throw ImportError.message("Couldn’t work out where you are. If you’re indoors, try again near a window — on a simulator, set a location in Features › Location.")
            }
        }
    }

    /// Only the categories this app can actually spend in. Anything else — a park, a school — is not
    /// somewhere a card gets used, so it is left out rather than filed under Other.
    static func category(for poi: MKPointOfInterestCategory) -> SpendingCategory? {
        switch poi {
        case .restaurant, .cafe, .bakery, .brewery, .winery, .nightlife: return .food
        case .foodMarket: return .groceries
        case .gasStation, .evCharger, .parking, .publicTransport, .airport, .carRental, .hotel: return .transport
        // MapKit has one shop category, not a shelf of them, so every shop lands here.
        case .store, .laundry: return .shopping
        case .pharmacy, .hospital, .fitnessCenter: return .health
        case .movieTheater, .theater, .museum, .amusementPark, .stadium, .zoo, .aquarium: return .fun
        case .school, .university, .library: return .education
        default: return nil
        }
    }
}

/// One location fix, once. `CLLocationManager` answers through a delegate, so the callback is
/// bridged to a continuation rather than letting a delegate leak into the rest of the app.
///
/// Main-actor bound on purpose: built on a background executor the manager has no run loop to
/// deliver on, and the delegate is simply never called — the request hangs rather than failing.
@MainActor
private final class LocationReading: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private static var live: LocationReading?

    static func current() async throws -> CLLocation {
        let reader = LocationReading()
        live = reader
        defer { live = nil }
        return try await reader.read()
    }

    private func read() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(.failure(ImportError.message("samgloyim doesn’t have permission to use your location. You can turn it on in Settings.")))
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: finish(.failure(ImportError.message("samgloyim doesn’t have permission to use your location. You can turn it on in Settings.")))
        default: manager.requestLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        finish(.success(location))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }
}
