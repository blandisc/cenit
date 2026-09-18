// FER-521 · Ola 3 — watchOS WidgetKit extension: accessoryRectangular complication.

import SwiftUI
import WidgetKit

@main
struct CenitWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrainVerdictComplication()
    }
}
