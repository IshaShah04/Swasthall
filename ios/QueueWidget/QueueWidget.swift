import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), queueNumber: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), queueNumber: 1)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // Fetch data from Flutter via HomeWidget
        let sharedDefaults = UserDefaults(suiteName: "group.raunak.healthapp") // MUST MATCH APP GROUP ID
        let queueNumber = sharedDefaults?.integer(forKey: "queue_number") ?? 0
        
        let entry = SimpleEntry(date: Date(), queueNumber: queueNumber)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let queueNumber: Int
}

struct QueueWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Text("Current Queue")
                .font(.caption)
            Text("\(entry.queueNumber)")
                .font(.largeTitle)
                .bold()
        }
    }
}

struct QueueWidget: Widget {
    let kind: String = "QueueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            QueueWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Queue Status")
        .description("Track your clinic appointment.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
