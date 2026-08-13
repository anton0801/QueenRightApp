//
//  LocationService.swift
//  QueenRight
//
//  CoreLocation, requested ONCE and only at apiary setup (§5.5, acceptance 13) — never
//  in onboarding's teaching pages and never at launch. Search-by-name is always
//  available as an equal path, so a refusal costs the user nothing.
//

import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle
        case asking
        case denied
        case failed
        case got(latitude: Double, longitude: Double)
    }

    @Published private(set) var status: Status = .idle

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // an apiary is a field, not a doorstep
    }

    /// Ask for the apiary's position. Coarse accuracy is plenty — the forage model
    /// works on a whole-site scale.
    func requestOnce() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .asking
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            status = .asking
            manager.requestLocation()
        @unknown default:
            status = .failed
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch auth {
            case .authorizedAlways, .authorizedWhenInUse:
                self.status = .asking
                manager.requestLocation()
            case .denied, .restricted:
                self.status = .denied
            case .notDetermined:
                break
            @unknown default:
                self.status = .failed
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let lat = last.coordinate.latitude
        let lon = last.coordinate.longitude
        Task { @MainActor [weak self] in
            self?.status = .got(latitude: lat, longitude: lon)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            // A failure is not an error state worth shouting about — the user can
            // always type the site name instead.
            self?.status = .failed
        }
    }
}
