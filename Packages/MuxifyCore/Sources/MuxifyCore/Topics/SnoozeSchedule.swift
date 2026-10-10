import Foundation

public enum SnoozeSchedule: Equatable {
    case relative(Int, Calendar.Component)
    case day(Int, hour: Int, minute: Int)
    case weekday(Int, hour: Int, minute: Int)
    /// The next time the clock shows this hour and minute: today if it is still ahead, else tomorrow.
    case next(hour: Int, minute: Int)
    case never

    public init?(_ text: String, typed: Bool = false) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text == "never" { self = .never; return }
        let relative = text.hasPrefix("+") ? String(text.dropFirst()) : (typed ? text : "")
        if let unit = relative.last, let count = Int(relative.dropLast()), count > 0,
           relative.dropLast().allSatisfy(\.isNumber), count <= 1_000_000 {
            let components: [Character: Calendar.Component] = ["m": .minute, "h": .hour, "d": .day]
            if let component = components[unit] { self = .relative(count, component); return }
        }
        if let clock = Self.clock(text[...]) { self = .next(hour: clock.hour, minute: clock.minute); return }
        guard let day = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let rest = text.dropFirst(day.count).drop(while: \.isWhitespace)
        var hour = 9, minute = 0
        if !rest.isEmpty {
            guard let clock = Self.clock(rest) else { return nil }
            hour = clock.hour; minute = clock.minute
        }
        switch day {
        case "today": self = .day(0, hour: hour, minute: minute)
        case "tomorrow": self = .day(1, hour: hour, minute: minute)
        default:
            guard let index = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].firstIndex(of: String(day)) else { return nil }
            self = .weekday(index + 1, hour: hour, minute: minute)
        }
    }

    /// Reads H, HH, HMM, HHMM, H:MM or HH:MM, each with an optional am or pm.
    private static func clock(_ text: Substring) -> (hour: Int, minute: Int)? {
        let meridiem = ["am", "pm"].first { text.hasSuffix($0) }
        var digits = meridiem == nil ? text : text.dropLast(2)
        while digits.last?.isWhitespace == true { digits = digits.dropLast() }
        let pieces = digits.split(separator: ":", omittingEmptySubsequences: false)
        let hourText: Substring, minuteText: Substring
        switch (pieces.count, digits.count) {
        case (1, 1...2): hourText = digits; minuteText = "0"
        case (1, 3...4): hourText = digits.dropLast(2); minuteText = digits.suffix(2)
        case (2, _) where (1...2).contains(pieces[0].count) && pieces[1].count == 2: hourText = pieces[0]; minuteText = pieces[1]
        default: return nil
        }
        guard (hourText + minuteText).allSatisfy({ $0.isASCII && $0.isNumber }),
              let hour = Int(hourText), let minute = Int(minuteText), (0...59).contains(minute) else { return nil }
        guard let meridiem else { return (0...23).contains(hour) ? (hour, minute) : nil }
        guard (1...12).contains(hour) else { return nil }
        return (hour % 12 + (meridiem == "pm" ? 12 : 0), minute)
    }

    public func deadline(from now: Date, calendar: Calendar = .current) -> SnoozeDeadline? {
        switch self {
        case .never: return .never
        case .relative(let count, let component):
            return calendar.date(byAdding: component, value: count, to: now).map(SnoozeDeadline.at)
        case .day(let offset, let hour, let minute):
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), date > now else { return nil }
            return .at(date)
        case .next(let hour, let minute):
            return calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute),
                                     matchingPolicy: .nextTime).map(SnoozeDeadline.at)
        case .weekday(let weekday, let hour, let minute):
            return calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                                     matchingPolicy: .nextTime).map(SnoozeDeadline.at)
        }
    }
}

public enum SnoozeDeadline: Equatable {
    case at(Date), never

    public init?(stored: String) {
        if stored == "never" { self = .never; return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: stored)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: stored) else { return nil }
        self = .at(date)
    }

    public var stored: String {
        switch self {
        case .never: return "never"
        case .at(let date): return ISO8601DateFormatter().string(from: date)
        }
    }

    public func isDue(at now: Date) -> Bool {
        if case .at(let date) = self { return date <= now }
        return false
    }

    public var description: String {
        switch self {
        case .never: return "Until I unsnooze"
        case .at(let date): return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// The short wake time a Snoozed Topic row shows: "Mon 9:00", or "never".
    public var wakeLabel: String {
        switch self {
        case .never: return "never"
        case .at(let date): return date.formatted(Date.FormatStyle().weekday(.abbreviated).hour(.defaultDigits(amPM: .omitted)).minute())
        }
    }
}

public struct SnoozePreset: Equatable {
    public let label: String
    public let schedule: SnoozeSchedule

    public static let defaults = [
        SnoozePreset(label: "In one hour", schedule: .relative(1, .hour)),
        SnoozePreset(label: "Tomorrow", schedule: .day(1, hour: 9, minute: 0)),
        SnoozePreset(label: "Next Monday", schedule: .weekday(2, hour: 9, minute: 0)),
    ]
}
