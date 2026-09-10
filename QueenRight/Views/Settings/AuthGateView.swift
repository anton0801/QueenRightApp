//
//  AuthGateView.swift
//  QueenRight
//
//  Полноэкранный вход. Показывается после сплеша, когда сервер ответил, что
//  сессии нет: без аккаунта дальше не пускаем (решение владельца).
//
//  Экран нарисован в языке приложения — соты, мёд и дым, серифный дисплей, —
//  потому что это ПЕРВОЕ, что видит человек, и выглядеть чужой формой он не
//  должен. Причина, по которой аккаунт вообще нужен, названа словами: иначе
//  требование входа в приложении для одного пасечника выглядит произволом.
//

import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmed.isEmpty && password.count >= 8 && auth.phase != .authenticating
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                CombGround()
                
                Image("welcome")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .ignoresSafeArea()
                    .blur(radius: 2)
                    .opacity(0.1)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.gap) {
                        header
                        fields
                        messages
                        actions
                        reason
                    }
                    .padding(Space.screen)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .onValueChange(of: isSignUp) { _ in auth.clearMessages() }
        }
        .ignoresSafeArea()
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Hexagon()
                .fill(Palette.accent)
                .frame(width: 34, height: 38)
                .overlay(Hexagon().stroke(Palette.accentMuted, lineWidth: 1))
                .padding(.bottom, Space.tight)

            Text(isSignUp ? "Create your apiary" : "Welcome back")
                .font(Typo.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(isSignUp
                 ? "An apiary is usually two people and always more than one season."
                 : "Sign in and your hives come with you.")
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.section)
    }

    // MARK: - Поля

    private var fields: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            VStack(alignment: .leading, spacing: Space.tight) {
                Text("Email")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)
                TextField("", text: $email,
                          prompt: Text("you@example.com")
                            .foregroundColor(Palette.textSecondary))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(Space.row)
                    .combPanel(fill: Palette.surfaceElevated,
                               stroke: focus == .email ? Palette.accent : Palette.hairline)
            }

            VStack(alignment: .leading, spacing: Space.tight) {
                Text("Password")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)
                SecureField("", text: $password,
                            prompt: Text(isSignUp ? "At least 8 characters" : "Your password")
                              .foregroundColor(Palette.textSecondary))
                    .textContentType(isSignUp ? .newPassword : .password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(Space.row)
                    .combPanel(fill: Palette.surfaceElevated,
                               stroke: focus == .password ? Palette.accent : Palette.hairline)

                if isSignUp {
                    Text("Eight characters or more. Length beats punctuation.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Сообщения

    @ViewBuilder
    private var messages: some View {
        if let message = auth.errorMessage {
            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Palette.imminent)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let info = auth.infoMessage {
            Text(info)
                .font(Typo.caption)
                .foregroundStyle(Palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Кнопки

    private var actions: some View {
        VStack(spacing: Space.row) {
            Button(buttonTitle) { submit() }
                .buttonStyle(HoneyButtonStyle())
                .disabled(!canSubmit)

            Button(isSignUp ? "I already have an account" : "Create an account") {
                withAnimation(.comb) { isSignUp.toggle() }
            }
            .font(Typo.captionMed)
            .foregroundStyle(Palette.textPrimary)

            if !isSignUp {
                Button("Forgotten your password?") {
                    auth.sendPasswordReset(email: email)
                }
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .disabled(email.trimmed.isEmpty)
            }
        }
    }

    private var buttonTitle: String {
        if auth.phase == .authenticating { return "One moment…" }
        return isSignUp ? "Create account" : "Sign in"
    }

    // MARK: - Зачем это нужно

    private var reason: some View {
        NotePanel(text: "Your inspections, and the laying rate this app learns for each queen, follow you — not this phone. Two people can work the same apiary and see the same hive state at the hive.")
            .padding(.top, Space.tight)
    }

    // MARK: -

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        if isSignUp {
            auth.signUp(email: email.trimmed, password: password)
        } else {
            auth.signIn(email: email.trimmed, password: password)
        }
    }
}

#Preview {
    AuthGateView().environmentObject(AuthService())
}
