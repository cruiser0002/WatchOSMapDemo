import Foundation
import CoreLocation
import Combine

public final class LocationHeadingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public var userLocation: CLLocation?
    @Published public var userHeading: CLHeading?
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var isUpdating: Bool = false
    
    private let locationManager = CLLocationManager()
    
    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0 // 1 meter update sensitivity
        #if os(watchOS) || os(iOS)
        locationManager.headingFilter = 2.0  // 2 degree heading sensitivity
        #endif
    }
    
    public func requestPermissions() {
        #if os(watchOS) || os(iOS)
        locationManager.requestWhenInUseAuthorization()
        #else
        locationManager.requestAlwaysAuthorization()
        #endif
    }
    
    public func startUpdates() {
        guard !isUpdating else { return }
        locationManager.startUpdatingLocation()
        #if os(watchOS) || os(iOS)
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        #endif
        isUpdating = true
    }
    
    public func stopUpdates() {
        locationManager.stopUpdatingLocation()
        #if os(watchOS) || os(iOS)
        if CLLocationManager.headingAvailable() {
            locationManager.stopUpdatingHeading()
        }
        #endif
        isUpdating = false
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        #if os(watchOS) || os(iOS)
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startUpdates()
        }
        #else
        if manager.authorizationStatus == .authorizedAlways {
            startUpdates()
        }
        #endif
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        self.userLocation = latest
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        self.userHeading = newHeading
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Failed with error: \(error.localizedDescription)")
    }
}
