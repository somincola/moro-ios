//
//  Date+Extensions.swift
//  moro
//
//  Date formatting extensions for the app.
//

import Foundation

extension Date {
    /// Returns a human-readable relative time string (e.g., "2h", "3d", "1w")
    var relativeFormatted: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        
        // Future dates
        if interval < 0 {
            return "now"
        }
        
        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        let months = days / 30
        let years = days / 365
        
        if seconds < 60 {
            return "now"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else if hours < 24 {
            return "\(hours)h"
        } else if days < 7 {
            return "\(days)d"
        } else if weeks < 4 {
            return "\(weeks)w"
        } else if months < 12 {
            return "\(months)mo"
        } else {
            return "\(years)y"
        }
    }
    
    /// Returns a full formatted date string (e.g., "2025年11月25日 14:30")
    var fullFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Returns time only (e.g., "14:30")
    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Returns date only (e.g., "Nov 25, 2025")
    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

