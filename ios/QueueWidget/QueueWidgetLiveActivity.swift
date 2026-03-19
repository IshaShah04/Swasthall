import ActivityKit
import WidgetKit
import SwiftUI

struct QueueWidgetAttributes: ActivityAttributes {
    
    public struct ContentState: Codable, Hashable {
        var queueNumber: Int
        var status: String
    }

    var patientName: String
}

@available(iOS 16.1, *)
struct QueueWidgetLiveActivity: Widget {
    
    var body: some WidgetConfiguration {
        
        ActivityConfiguration(for: QueueWidgetAttributes.self) { context in
            
            // 🔒 LOCK SCREEN VIEW
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Patient")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(context.attributes.patientName)
                            .font(.headline)
                        
                        Text(context.state.status)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Text("Number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(context.state.queueNumber)")
                            .font(.system(size: 28, weight: .bold))
                    }
                }
            }
            .padding()
            
        } dynamicIsland: { context in
            
            DynamicIsland {
                
                // Expanded Island
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.attributes.patientName)
                            .font(.headline)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text("#\(context.state.queueNumber)")
                        .font(.title2)
                        .bold()
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Status: \(context.state.status)")
                        .font(.subheadline)
                }
                
            } compactLeading: {
                Text("#\(context.state.queueNumber)")
                    .bold()
            } compactTrailing: {
                Image(systemName: "person.fill")
            } minimal: {
                Text("\(context.state.queueNumber)")
                    .bold()
            }
        }
    }
}
