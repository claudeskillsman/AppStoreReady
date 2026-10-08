import WidgetKit
import SwiftUI

struct CartProvider: TimelineProvider {
    private let shared = UserDefaults(suiteName: "group.com.acme.shop")

    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .atEnd))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}
