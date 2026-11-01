//
//  CalendarDatePickerView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI

struct CalendarDatePickerView: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    
    @State private var currentMonth: Date
    @State private var tempSelectedDate: Date
    
    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }()
    
    init(selectedDate: Binding<Date>, isPresented: Binding<Bool>) {
        self._selectedDate = selectedDate
        self._isPresented = isPresented
        _currentMonth = State(initialValue: selectedDate.wrappedValue)
        _tempSelectedDate = State(initialValue: selectedDate.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month Header with Navigation
                HStack {
                    Button(action: {
                        changeMonth(-1)
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        // Show month/year picker or just allow navigation
                    }) {
                        Text(monthYearString)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        changeMonth(1)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                // Weekday Headers
                HStack(spacing: 0) {
                    let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Calendar Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(daysInMonth, id: \.self) { date in
                        DayPickerCellView(
                            date: date,
                            isToday: calendar.isDateInToday(date),
                            isCurrentMonth: calendar.isDate(date, equalTo: currentMonth, toGranularity: .month),
                            isSelected: calendar.isDate(date, inSameDayAs: tempSelectedDate),
                            onTap: {
                                Haptics.selection()
                                tempSelectedDate = date
                            }
                        )
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .background(Color.screenBackground)
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassConfirmButton(accessibilityLabelText: "Done") {
                        selectedDate = tempSelectedDate
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func changeMonth(_ direction: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: direction, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth).localizedCapitalized
    }
    
    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstDay = calendar.dateInterval(of: .month, for: currentMonth)?.start else {
            return []
        }
        
        let firstDayWeekday = calendar.component(.weekday, from: firstDay)
        let daysToSubtract = (firstDayWeekday - calendar.firstWeekday + 7) % 7
        
        guard let startDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDay) else {
            return []
        }
        
        var days: [Date] = []
        var currentDate = startDate
        
        for _ in 0..<42 { // 6 weeks
            days.append(currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        return days
    }
}

struct DayPickerCellView: View {
    let date: Date
    let isToday: Bool
    let isCurrentMonth: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: onTap) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: (isToday || isSelected) ? .bold : .regular))
                .foregroundColor(
                    isSelected ? Color.screenBackground :
                    (isToday ? Color.primaryText :
                    (isCurrentMonth ? Color.primaryText : .gray))
                )
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isSelected ? Color.primaryText : (isToday ? Color.blue.opacity(0.3) : Color.clear))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

