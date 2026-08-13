//
//  NotificationOfferView.swift
//  QueenRight
//
//  Экран-оффер уведомлений. Показывается ТОЛЬКО когда внешний сервис вернул
//  адрес — то есть в спец-потоке. В обычном потоке разрешение на уведомления
//  спрашивается позже, из Настроек.
//
//  Правило показа:
//   • «Разрешить» → системный запрос. При ЛЮБОМ ответе, включая отказ, экран
//     больше не показывается: человек уже принял решение, и повторять вопрос
//     после отказа — навязчивость, за которую снимают с публикации.
//   • «Не сейчас» первый раз → спросим ещё раз через три дня.
//   • «Не сейчас» во второй раз → больше никогда.
//

import SwiftUI

enum NotificationOffer {

    private static let doneKey = "qr_offer_done"
    private static let firstSkipKey = "qr_offer_first_skip_at"
    private static let repeatAfterDays = 3

    /// Показывать ли экран сейчас.
    static var shouldShow: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: doneKey) { return false }

        guard let firstSkip = defaults.object(forKey: firstSkipKey) as? Date else {
            return true   // ещё не отказывались
        }
        // Отказались один раз — ждём три дня, потом единственный повтор.
        let due = Calendar.current.date(byAdding: .day, value: repeatAfterDays, to: firstSkip)
        return due.map { Date() >= $0 } ?? false
    }

    /// Вопрос закрыт навсегда.
    static func finish() {
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    /// Отложить. Второй отказ закрывает вопрос окончательно.
    static func skip() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: firstSkipKey) as? Date == nil {
            defaults.set(Date(), forKey: firstSkipKey)
        } else {
            finish()
        }
    }

    #if DEBUG
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: doneKey)
        UserDefaults.standard.removeObject(forKey: firstSkipKey)
    }
    #endif
}

struct NotificationOfferView: View {
    var onFinished: () -> Void

    @State private var busy = false

    var body: some View {
        ZStack {
            CombGround()

            VStack(alignment: .leading, spacing: Space.gap) {
                Spacer(minLength: 0)

                Hexagon()
                    .fill(Palette.accent)
                    .frame(width: 40, height: 45)
                    .overlay {
                        Image(systemName: "bell")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.onAccent)
                    }

                Text("A swarm gives you a day, not a week")
                    .font(Typo.display)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Turn on notifications and the app tells you the moment a colony crosses into imminent — and when a hive has gone long enough without a look that the clock is guessing. Nothing else.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                VStack(spacing: Space.row) {
                    Button(busy ? "One moment…" : "Turn them on") { allow() }
                        .buttonStyle(HoneyButtonStyle())
                        .disabled(busy)

                    Button("Not now") { skip() }
                        .font(Typo.captionMed)
                        .foregroundStyle(Palette.textSecondary)
                        .disabled(busy)
                }
            }
            .padding(Space.screen)
        }
    }

    private func allow() {
        busy = true
        Task {
//            _ = await SwarmAlerts.requestPermission()
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            NotificationOffer.finish()
            busy = false
            onFinished()
        }
    }

    private func skip() {
        NotificationOffer.skip()
        onFinished()
    }
    
}

#Preview {
    NotificationOfferView {}
}
