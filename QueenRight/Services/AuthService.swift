//
//  AuthService.swift
//  QueenRight
//
//  Аккаунты через собственный API (PHP + MySQL). Пришло на смену FirebaseAuth.
//
//  Аккаунт здесь по-прежнему НЕ обязателен: пасека, борт и захват рамки живут
//  локально и не спрашивают сеть. Вход нужен ради двух вещей из ТЗ §14 —
//  пасеки на двоих и переноса выученной скорости червления между устройствами.
//

import Foundation
import Combine

enum AuthPhase: Equatable {
    /// Адрес API не настроен в сборке — синхронизации нет, всё работает локально.
    case notConfigured
    case signedOut
    case authenticating
    case signedIn
}

@MainActor
final class AuthService: ObservableObject {

    @Published private(set) var phase: AuthPhase
    @Published private(set) var userId: String?
    @Published private(set) var email: String?
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    /// Роль в пасеке: владелец может удалить её и исключать участников.
    @Published private(set) var role: String?

    init() {
        if !Self.isConfigured {
            phase = .notConfigured
        } else {
            phase = TokenStore.hasSession ? .signedIn : .signedOut
            if TokenStore.hasSession {
                Task { await refreshProfile() }
            }
        }
    }

    /// Пустой или демонстрационный адрес API означает сборку без синхронизации.
    static var isConfigured: Bool {
        let host = APIConfig.baseURL.host ?? ""
        return !host.isEmpty && host != "api.example.com"
    }

    /// Показывается в Настройках → АККАУНТ, когда синхронизации нет.
    static var explanation: String {
        isConfigured
            ? ""
            : "Sync isn’t set up in this build. Everything works locally: hives, the swarm clock and frame capture are stored on this device."
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: - Вход и регистрация

    func signIn(email address: String, password: String) {
        guard Self.isConfigured else { return }
        clearMessages()
        phase = .authenticating

        Task {
            do {
                let response: AuthResponse = try await APIClient.shared.send(
                    "auth/login",
                    method: "POST",
                    body: ["email": address, "password": password],
                    authorised: false,
                    as: AuthResponse.self
                )
                applySession(response)
                Haptics.swarmAverted()
            } catch {
                fail(error)
            }
        }
    }

    func signUp(email address: String, password: String) {
        guard Self.isConfigured else { return }
        clearMessages()
        phase = .authenticating

        Task {
            do {
                let response: AuthResponse = try await APIClient.shared.send(
                    "auth/register",
                    method: "POST",
                    body: ["email": address, "password": password],
                    authorised: false,
                    as: AuthResponse.self
                )
                applySession(response)
                Haptics.swarmAverted()
            } catch {
                fail(error)
            }
        }
    }

    func sendPasswordReset(email address: String) {
        guard Self.isConfigured else { return }
        clearMessages()

        Task {
            // Сервер отвечает 204 независимо от того, есть такой адрес или нет,
            // и сообщение здесь такое же — иначе форма стала бы проверялкой адресов.
            _ = try? await APIClient.shared.sendNoContent(
                "auth/password/forgot",
                body: ["email": address],
                authorised: false
            )
            infoMessage = "If an account with that address exists, an email is on its way."
        }
    }

    func signOut() {
        guard Self.isConfigured else { return }
        let refresh = TokenStore.refreshToken

        Task {
            if let refresh {
                _ = try? await APIClient.shared.sendNoContent(
                    "auth/logout",
                    body: ["refresh_token": refresh],
                    authorised: false
                )
            }
        }

        TokenStore.clear()
        userId = nil
        email = nil
        role = nil
        phase = .signedOut
        clearMessages()
    }

    func changePassword(current: String, next: String) {
        guard Self.isConfigured else { return }
        clearMessages()

        Task {
            do {
                let tokens: TokenPair = try await APIClient.shared.send(
                    "auth/password",
                    method: "POST",
                    body: ["current_password": current, "new_password": next],
                    as: TokenPair.self
                )
                // Сервер отзывает все прежние сессии, поэтому берём свежую пару.
                TokenStore.accessToken = tokens.access_token
                TokenStore.refreshToken = tokens.refresh_token
                infoMessage = "Password changed. You’ll need to sign in again on your other devices."
                Haptics.swarmAverted()
            } catch {
                fail(error)
            }
        }
    }

    /// §14 и App Review 5.1.1 — удаление в два касания, с подтверждением паролем.
    func deleteAccount(password: String, completion: @escaping (Bool) -> Void) {
        guard Self.isConfigured else {
            // Без backend удалять на сервере нечего — локальные данные сотрёт вызывающий.
            completion(true)
            return
        }
        clearMessages()

        Task {
            do {
                _ = try await APIClient.shared.sendNoContent(
                    "auth/account",
                    method: "DELETE",
                    body: ["password": password]
                )
                TokenStore.clear()
                userId = nil
                email = nil
                role = nil
                phase = .signedOut
                completion(true)
            } catch {
                fail(error)
                Haptics.error()
                completion(false)
            }
        }
    }

    // MARK: - Профиль

    func refreshProfile() async {
        guard Self.isConfigured, TokenStore.hasSession else { return }
        do {
            let me: MeResponse = try await APIClient.shared.send("auth/me", as: MeResponse.self)
            userId = me.user.id
            email = me.user.email
            role = me.apiary?.role
            phase = .signedIn
        } catch APIError.unauthorized {
            TokenStore.clear()
            phase = .signedOut
        } catch {
            // Офлайн — не повод выкидывать пользователя из аккаунта.
        }
    }

    // MARK: - Внутреннее

    private func applySession(_ response: AuthResponse) {
        TokenStore.accessToken = response.access_token
        TokenStore.refreshToken = response.refresh_token
        userId = response.user.id
        email = response.user.email
        phase = .signedIn
        Task { await refreshProfile() }
    }

    private func fail(_ error: Error) {
        phase = TokenStore.hasSession ? .signedIn : .signedOut
        errorMessage = (error as? APIError)?.userMessage ?? "Something went wrong. Please try again."
        Haptics.error()
    }
}
