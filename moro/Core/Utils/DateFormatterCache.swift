//
//  DateFormatterCache.swift
//  moro
//
//  Cached date formatters for improved performance.
//  Creating DateFormatter instances is expensive, so we cache them for reuse.
//

import Foundation

/// Actor-based cache for date formatters to improve performance
actor DateFormatterCache {
    static let shared = DateFormatterCache()

    // MARK: - Private Formatter Storage

    /// ISO8601 formatter for parsing API dates
    private lazy var _iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO8601 formatter without fractional seconds (fallback)
    private lazy var _iso8601FormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Relative date formatter for "2 hours ago" style
    private lazy var _relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Full relative date formatter for "2 hours ago" style (full words)
    private lazy var _fullRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Date formatter for displaying dates (e.g., "Dec 17, 2024")
    private lazy var _displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Date-time formatter for displaying dates with time (e.g., "Dec 17, 2024 at 10:30 AM")
    private lazy var _displayDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Time-only formatter (e.g., "10:30 AM")
    private lazy var _timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Accessors

    /// ISO8601 formatter for parsing API dates
    var iso8601Formatter: ISO8601DateFormatter {
        _iso8601Formatter
    }

    /// ISO8601 formatter without fractional seconds
    var iso8601FormatterNoFractional: ISO8601DateFormatter {
        _iso8601FormatterNoFractional
    }

    /// Relative date formatter (abbreviated)
    var relativeFormatter: RelativeDateTimeFormatter {
        _relativeFormatter
    }

    /// Relative date formatter (full words)
    var fullRelativeFormatter: RelativeDateTimeFormatter {
        _fullRelativeFormatter
    }

    /// Medium date formatter
    var displayDateFormatter: DateFormatter {
        _displayDateFormatter
    }

    /// Date-time formatter
    var displayDateTimeFormatter: DateFormatter {
        _displayDateTimeFormatter
    }

    /// Time-only formatter
    var timeOnlyFormatter: DateFormatter {
        _timeOnlyFormatter
    }

    // MARK: - Parsing Methods

    /// Parse an ISO8601 date string, trying with and without fractional seconds
    func parseISO8601(_ string: String) -> Date? {
        if let date = _iso8601Formatter.date(from: string) {
            return date
        }
        return _iso8601FormatterNoFractional.date(from: string)
    }

    // MARK: - Formatting Methods

    /// Format a date as relative time (e.g., "2h ago")
    func relativeString(for date: Date) -> String {
        _relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Format a date as full relative time (e.g., "2 hours ago")
    func fullRelativeString(for date: Date) -> String {
        _fullRelativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Format a date for display (e.g., "Dec 17, 2024")
    func displayString(for date: Date) -> String {
        _displayDateFormatter.string(from: date)
    }

    /// Format a date-time for display (e.g., "Dec 17, 2024 at 10:30 AM")
    func displayDateTimeString(for date: Date) -> String {
        _displayDateTimeFormatter.string(from: date)
    }

    /// Format time only (e.g., "10:30 AM")
    func timeString(for date: Date) -> String {
        _timeOnlyFormatter.string(from: date)
    }

    /// Smart relative string - shows relative for recent dates, absolute for older ones
    func smartRelativeString(for date: Date, cutoff: TimeInterval = 86400) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < cutoff {
            return relativeString(for: date)
        } else {
            return displayString(for: date)
        }
    }
}

// MARK: - Non-Actor Convenience Wrappers

/// Thread-local ISO8601 parser used in high-frequency decode paths.
nonisolated private enum APIISO8601DateParser {
    private static let withFractionalKey = "com.moro.date.iso8601.with-fractional"
    private static let withoutFractionalKey = "com.moro.date.iso8601.no-fractional"

    static func parse(_ string: String) -> Date? {
        let threadDictionary = Thread.current.threadDictionary

        let formatterWithFractional: ISO8601DateFormatter
        if let cached = threadDictionary[withFractionalKey] as? ISO8601DateFormatter {
            formatterWithFractional = cached
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            threadDictionary[withFractionalKey] = formatter
            formatterWithFractional = formatter
        }

        if let date = formatterWithFractional.date(from: string) {
            return date
        }

        let formatterWithoutFractional: ISO8601DateFormatter
        if let cached = threadDictionary[withoutFractionalKey] as? ISO8601DateFormatter {
            formatterWithoutFractional = cached
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            threadDictionary[withoutFractionalKey] = formatter
            formatterWithoutFractional = formatter
        }

        return formatterWithoutFractional.date(from: string)
    }
}

/// Synchronous date formatting utilities using cached formatters
/// Use these for quick formatting in synchronous contexts. Nonisolated: model decoding
/// calls `parseISO8601` on the background decode queue. The shared formatters are only
/// used to format, which Foundation formatters support from any thread.
nonisolated enum DateFormatting {

    nonisolated(unsafe) private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Parse ISO8601 date string synchronously
    static func parseISO8601(_ string: String) -> Date? {
        APIISO8601DateParser.parse(string)
    }

    /// Get relative time string synchronously
    static func relativeString(for date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }

    /// Get smart relative string synchronously
    static func smartRelativeString(for date: Date, cutoff: TimeInterval = 86400) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < cutoff {
            return relativeString(for: date)
        } else {
            // For older dates, use a simple format
            return dateString(from: date)
        }
    }

    // MARK: - Date/Time Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Get date string (e.g., "Dec 17, 2024")
    static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Get date-time string (e.g., "Dec 17, 2024 at 10:30 AM")
    static func dateTimeString(from date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    /// Get time-only string (e.g., "10:30 AM")
    static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

// MARK: - Date Extension

extension Date {
    /// Get a relative time string for this date
    var relativeString: String {
        DateFormatting.relativeString(for: self)
    }

    /// Get a smart relative string (relative for recent, absolute for older)
    func smartRelativeString(cutoff: TimeInterval = 86400) -> String {
        DateFormatting.smartRelativeString(for: self, cutoff: cutoff)
    }
}
