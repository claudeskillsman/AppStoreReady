import CoreLocation

// Excluded from the widget target; only used by Xcode previews.
let previewManager: CLLocationManager = {
    let manager = CLLocationManager()
    manager.requestWhenInUseAuthorization()
    return manager
}()
