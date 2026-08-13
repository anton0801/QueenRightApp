//
//  Typography.swift
//  QueenRight
//
//  Serif display + SF body + tabular figures (§3). Hive records are among the oldest
//  continuous farm records kept by hand — the serif is the field-notebook voice, so a
//  hive record looks KEPT rather than computed.
//  Every figure in the app is tabular so a column of hives compares straight down the page.
//

import SwiftUI
import UIKit

enum Typo {
    /// Scale a base point size with Dynamic Type, capped so the stack geometry survives XL.
    static func scaled(_ size: CGFloat, cap: CGFloat = 1.6) -> CGFloat {
        min(UIFontMetrics.default.scaledValue(for: size), size * cap)
    }

    // MARK: Display — swarm window, day counts, cell counts

    /// 34pt semibold serif, tracking 0 (§3).
    static var display: Font    { .system(size: scaled(34), weight: .semibold, design: .serif) }
    static var displaySm: Font  { .system(size: scaled(26), weight: .semibold, design: .serif) }

    // MARK: Title — serif medium 20pt

    static var title: Font      { .system(size: scaled(20), weight: .medium, design: .serif) }
    static var titleSm: Font    { .system(size: scaled(17), weight: .medium, design: .serif) }

    // MARK: Body — plain SF

    static var body: Font       { .system(size: scaled(16), weight: .regular) }
    static var bodyMedium: Font { .system(size: scaled(16), weight: .medium) }
    static var caption: Font    { .system(size: scaled(13), weight: .regular) }
    static var captionMed: Font { .system(size: scaled(13), weight: .medium) }

    /// Sentence-case section labels, lightly tracked.
    static var label: Font      { .system(size: scaled(12), weight: .semibold) }

    // MARK: Figures — ALWAYS tabular (§3, §10.5)

    /// The big number: days remaining, cell counts.
    static var figureDisplay: Font { .system(size: scaled(34), weight: .semibold, design: .serif).monospacedDigit() }
    static var figureLarge: Font   { .system(size: scaled(26), weight: .semibold, design: .serif).monospacedDigit() }
    static var figure: Font        { .system(size: scaled(17), weight: .medium).monospacedDigit() }
    static var figureSmall: Font   { .system(size: scaled(13), weight: .medium).monospacedDigit() }
}

// MARK: - Spacing

enum Space {
    static let hair: CGFloat    = 4
    static let tight: CGFloat   = 8
    static let row: CGFloat     = 12
    static let gap: CGFloat     = 16
    static let screen: CGFloat  = 20
    static let section: CGFloat = 28

    /// Frames redraw left to right within a box, 0.03s apart (§3).
    static let frameStagger: Double = 0.03
}

// MARK: - Number formatting (§10.5 — cells and days, never high/medium/low)

enum Fmt {
    /// Cell counts read as "37,800" with a thin space group separator.
    static func cells(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{2009}"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Whole-number percentage, e.g. "68%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// "9 days" / "1 day" — the unit is always spelled out.
    static func days(_ n: Int) -> String {
        n == 1 ? "1 day" : "\(n) days"
    }

    /// Short calendar date for a swarm window, e.g. "18 May".
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }

    /// Weekday name for the inspection queue, e.g. "Thursday".
    static func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f.string(from: date)
    }

    /// A dated window: "18–20 May", collapsing when both ends share a month.
    static func window(_ range: ClosedRange<Date>, calendar: Calendar = .current) -> String {
        if calendar.isDate(range.lowerBound, inSameDayAs: range.upperBound) {
            return day(range.lowerBound)
        }
        let lowerMonth = calendar.component(.month, from: range.lowerBound)
        let upperMonth = calendar.component(.month, from: range.upperBound)
        if lowerMonth == upperMonth {
            let d = calendar.component(.day, from: range.lowerBound)
            return "\(d)–\(day(range.upperBound))"
        }
        return "\(day(range.lowerBound)) – \(day(range.upperBound))"
    }
}
