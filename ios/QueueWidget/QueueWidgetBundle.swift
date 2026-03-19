import WidgetKit
import SwiftUI

@main
struct QueueWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            QueueWidgetLiveActivity()
        }
    }
}
