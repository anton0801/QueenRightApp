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
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                CombGround()
                
                Image("queenr")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .ignoresSafeArea()
                
                VStack(spacing: Space.gap) {
                    Spacer()
                    
                    Text("ALLOW NOTIFICATIONS ABOUT BONUSES AND PROMOS")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Stаy tunеd with bеst оffеrs frоm оur cаsinо")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .opacity(0.8)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: Space.row) {
                        Button {
                            allow()
                        } label: {
                            Image("queenrb")
                                .resizable()
                                .frame(width: 270, height: 55)
                        }
                        .disabled(busy)
                        
                        Button("Skip") { skip() }
                            .font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .opacity(0.8)
                            .disabled(busy)
                    }
                }
                .padding(Space.screen)
            }
        }
        .ignoresSafeArea()
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
