//
//  AlarmBar.swift
//  One
//

import SwiftUI

struct AlarmBar: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color.alarmOrange)

                Text("Alarms")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(Color.primaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.calendarSheetSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
