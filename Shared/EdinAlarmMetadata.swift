//
//  EdinAlarmMetadata.swift
//  One
//

import AlarmKit
import Foundation

/// Metadata shared by AlarmKit alarms and the snooze countdown Live Activity.
nonisolated struct EdinAlarmMetadata: AlarmMetadata {
    var label: String

    init(label: String = "Alarm") {
        self.label = label
    }
}
