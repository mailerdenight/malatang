import Foundation
import CoreLocation

/// 位置情報は「Appの使用中のみ」。拒否されても機能は止めない。
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isUndetermined: Bool {
        authorizationStatus == .notDetermined
    }

    func requestAuthorization() {
        guard isUndetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func requestOneShotLocation() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 取得できなくても店名手入力・地図検索は使えるので、黙って諦める。
        currentLocation = nil
    }
}
