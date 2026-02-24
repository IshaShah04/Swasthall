//
//  QueueWidgetBundle.swift
//  QueueWidget
//
//  Created by Raunak on 21/02/2026.
//

import WidgetKit
import SwiftUI

@main
struct QueueWidgetBundle: WidgetBundle {
    var body: some Widget {
        QueueWidget()
        QueueWidgetLiveActivity()
    }
}
