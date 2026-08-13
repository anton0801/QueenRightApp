//
//  SwarmAlerts.swift
//  QueenRight
//
//  Local notifications for the one thing worth interrupting someone about: a colony
//  crossing into imminent, or an inspection going stale enough that the clock is
//  guessing. Permission is asked for in context, from Settings — never in onboarding
//  (§10.8, acceptance 13).
//
//  These are scheduled locally rather than pushed, so they work at an apiary with no
//  signal, which is where the app is actually used.
//

import Foundation
import UserNotifications

enum SwarmAlerts {

    private static let imminentPrefix = "imminent-"
    private static let stalePrefix = "stale-"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asked for from Settings, at the moment the user turns alerts on.
    @discardableResult
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Rebuild every scheduled alert from the current state of the apiary. Called
    /// whenever a hive changes, so an alert never outlives the reason for it.
    static func reschedule(hives: [(hive: Hive, projection: SwarmProjection)]) async {
        let centre = UNUserNotificationCenter.current()
        guard await authorizationStatus() == .authorized else { return }

        let existing = await centre.pendingNotificationRequests()
        centre.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier))

        for entry in hives {
            if entry.projection.riskState == .imminent {
                await schedule(
                    id: imminentPrefix + entry.hive.id,
                    title: "\(entry.hive.name) is about to swarm",
                    body: entry.projection.reason,
                    at: soonestReasonableTime())
            }

            // One nudge when the projection turns into a guess.
            let daysUntilBlind = Confidence.blindAfterDays - entry.hive.daysSinceInspection()
            if daysUntilBlind > 0 {
                await schedule(
                    id: stalePrefix + entry.hive.id,
                    title: "\(entry.hive.name) needs a look",
                    body: "It's been \(Confidence.blindAfterDays) days. Past this the clock is guessing.",
                    at: Calendar.current.date(byAdding: .day, value: daysUntilBlind, to: Date()))
            }
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    /// Nobody wants to be told about a swarm at 3am. Alerts land at 8am, or in a
    /// minute if it is already the middle of the day.
    private static func soonestReasonableTime() -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        if (8...19).contains(hour) {
            return calendar.date(byAdding: .minute, value: 1, to: now)
        }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        if hour >= 20 {
            components.day = (components.day ?? 1) + 1
        }
        components.hour = 8
        components.minute = 0
        return calendar.date(from: components)
    }

    private static func schedule(id: String, title: String, body: String, at date: Date?) async {
        guard let date, date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
