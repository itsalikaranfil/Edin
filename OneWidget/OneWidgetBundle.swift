import WidgetKit
import SwiftUI

@main
struct OneWidgetBundle: WidgetBundle {
    var body: some Widget {
        OneDateWidget()
        OneTodaySmallWidget()
        OneTodayWidget()
        OneOverviewWidget()
        AlarmLiveActivity()
    }
}
