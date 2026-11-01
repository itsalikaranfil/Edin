//
//  MonthYearDropdownView.swift
//  One
//
//  Created by Ali Karanfil on 30.01.2026.
//

import SwiftUI

struct MonthYearDropdownView: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    
    @State private var selectedMonth: Int
    @State private var selectedYear: Int
    
    private let months: [String]
    
    private let years: [Int]
    
    private let calendar = Calendar.current
    
    init(selectedDate: Binding<Date>, isPresented: Binding<Bool>) {
        self._selectedDate = selectedDate
        self._isPresented = isPresented
        
        let currentYear = calendar.component(.year, from: selectedDate.wrappedValue)
        let currentMonth = calendar.component(.month, from: selectedDate.wrappedValue)
        
        _selectedMonth = State(initialValue: currentMonth - 1)
        _selectedYear = State(initialValue: currentYear)
        
        months = calendar.standaloneMonthSymbols
        
        let currentCalendarYear = calendar.component(.year, from: Date())
        years = Array((currentCalendarYear - 20)...(currentCalendarYear + 50))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Month Picker
            HStack(spacing: 12) {
                Text("Month")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(width: 60, alignment: .leading)
                
                Picker("Month", selection: $selectedMonth) {
                    ForEach(0..<12, id: \.self) { index in
                        Text(months[index])
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.primaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Year Picker
            HStack(spacing: 12) {
                Text("Year")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(width: 60, alignment: .leading)
                
                Picker("Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text("\(year)")
                            .tag(year)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.primaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .onChange(of: selectedMonth) { _, _ in
            applySelection()
        }
        .onChange(of: selectedYear) { _, _ in
            applySelection()
        }
    }
    
    private func applySelection() {
        var components = calendar.dateComponents([.day, .hour, .minute, .second], from: selectedDate)
        components.month = selectedMonth + 1
        components.year = selectedYear
        if let newDate = calendar.date(from: components) {
            selectedDate = newDate
        }
    }
}

