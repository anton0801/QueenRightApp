//
//  UnreachableView.swift
//  QueenRight
//
//  Экран, который видно вместо вечного спиннера, когда сервер не ответил.
//
//  Приложение по решению владельца не пускает внутрь без ответа сервера. Чтобы
//  это не превратилось в «приложение не открывается», отказ показывается словами
//  и с кнопкой повтора — человек видит, что происходит, и что делать.
//

import SwiftUI

struct UnreachableView: View {
    let message: String

    var body: some View {
        ZStack {
            CombGround()

            VStack(spacing: Space.gap) {
                Spacer()

                // Пустые соты — та же графика, что и на пустой пасеке.
                Hexagon()
                    .stroke(Palette.hairlineStrong, lineWidth: 1.5)
                    .frame(width: 68, height: 76)
                    .overlay {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Palette.textSecondary)
                    }

                VStack(spacing: Space.tight) {
                    Text("Can’t reach the server")
                        .font(Typo.display)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(Typo.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                Spacer()
            }
            .padding(Space.screen)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    UnreachableView(message: "Check your connection and try again.")
}
