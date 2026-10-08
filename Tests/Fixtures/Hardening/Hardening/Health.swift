import HealthKit

func requestHealth(store: HKHealthStore) {
    store.requestAuthorization(toShare: [], read: []) { _, _ in }
}
