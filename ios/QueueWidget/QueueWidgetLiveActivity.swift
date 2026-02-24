import ActivityKit
import WidgetKit
import SwiftUI

struct QueueWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic data that changes (e.g., your place in line)
        var queueNumber: Int
        var status: String
    }

    // Static data that doesn't change once started
    var patientName: String
}

struct QueueWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QueueWidgetAttributes.self) { context in
            // LOCK SCREEN VIEW
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Patient: \(context.attributes.patientName)")
                            .font(.headline)
                        Text(context.state.status)
                            .font(.subheadline)
                    }
                    Spacer()
                    VStack {
                        Text("Number")
                            .font(.caption)
                        Text("\(context.state.queueNumber)")
                            .font(.system(size: 24, weight: .bold))
                    }
                }
            }
            .padding()

        } dynamicIsland: { context in
            // DYNAMIC ISLAND VIEW (The pill at the top)
            DynamicIsland {
                ExpandedRegion(.leading) {
                    Text("P: \(context.attributes.patientName)")
                }
                ExpandedRegion(.trailing) {
                    Text("#\(context.state.queueNumber)")
                }
                ExpandedRegion(.bottom) {
                    Text("Status: \(context.state.status)")
                }
            } compactLeading: {
                Text("#\(context.state.queueNumber)")
            } compactTrailing: {
                Image(systemName: "person.2.fill")
            } minimal: {
                Text("\(context.state.queueNumber)")
            }
        }
    }
}
