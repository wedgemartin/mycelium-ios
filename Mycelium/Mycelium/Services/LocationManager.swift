import Foundation
import CoreLocation
import Observation

/// Captures the device's approximate location (city-level) so user-trained LoRA
/// adapters can be tagged with where their knowledge is relevant. Used at publish
/// time to set the catalog `lat`/`lng` — replacing the old hardcoded 0,0 ("null
/// island") which broke geographic discovery for user content.
///
/// Propagation *reach* is NOT set here — that's left to the network's adaptive
/// geo-radius + reputation system. This only records where the knowledge is about.
@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()
    var latitude: Double = 0
    var longitude: Double = 0
    var hasLocation: Bool = false
    var authorizationDenied: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer // city-level is enough
    }

    /// Request permission and start resolving location. Safe to call repeatedly.
    func requestAndUpdate() {
        manager.requestWhenInUseAuthorization()
        // Use last known fix immediately if available.
        if let last = manager.location {
            setLocation(last)
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private func setLocation(_ loc: CLLocation) {
        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        hasLocation = true
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        setLocation(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("location: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            authorizationDenied = false
            manager.startUpdatingLocation()
        case .denied, .restricted:
            authorizationDenied = true
        default:
            break
        }
    }
}
