//
//  Haptics.swift
//  QueenRight
//
//  The exact haptics the spec assigns (§5.1, §5.2, §5.3):
//   frame lifted → soft · action dropped → rigid · rectangle locked → selection
//   cell marked capped → warning · hive enters imminent → warning
//   imminent → calm → success, and ONLY that transition (§3 Celebration).
//

import UIKit

enum Haptics {
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(type)
    }

    /// A frame lifted off the board.
    static func frameLifted() { impact(.soft) }
    /// An action dropped onto the board.
    static func actionDropped() { impact(.rigid) }
    /// Vision locked onto the frame edges.
    static func rectangleLocked() { UISelectionFeedbackGenerator().selectionChanged() }
    /// A queen cell marked capped, or a hive crossing into imminent.
    static func warning() { notify(.warning) }
    /// Reserved for the single celebration: imminent → calm.
    static func swarmAverted() { notify(.success) }
    /// Generic light selection.
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func light() { impact(.light) }
    static func error() { notify(.error) }
}
