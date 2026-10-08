import AppTrackingTransparency

func askToTrack() {
    ATTrackingManager.requestTrackingAuthorization { _ in }
}
