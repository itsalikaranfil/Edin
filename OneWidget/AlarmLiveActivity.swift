//
//  AlarmLiveActivity.swift
//  OneWidget
//

import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<EdinAlarmMetadata>.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.label ?? "Alarm")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    remainingText(for: context.state)
                        .monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255))
            } compactTrailing: {
                remainingText(for: context.state)
                    .monospacedDigit()
                    .font(.caption2)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255))
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<AlarmAttributes<EdinAlarmMetadata>>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.metadata?.label ?? "Alarm")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(statusTitle(for: context.state))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer(minLength: 0)

            remainingText(for: context.state)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding()
    }

    private func statusTitle(for state: AlarmPresentationState) -> String {
        switch state.mode {
        case .countdown:
            return "Snoozed"
        case .paused:
            return "Paused"
        case .alert:
            return "Alarm"
        @unknown default:
            return "Alarm"
        }
    }

    @ViewBuilder
    private func remainingText(for state: AlarmPresentationState) -> some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
        case .paused(let paused):
            let remaining = max(0, Int(paused.totalCountdownDuration - paused.previouslyElapsedDuration))
            Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                .monospacedDigit()
        case .alert:
            Text("Now")
        @unknown default:
            Text("--:--")
        }
    }
}
