//
//  AccountView.swift
//  QueenRight
//
//  §5.5 ACCOUNT and §14. Email sign-in, apiary members, and account deletion in two
//  taps — Delete Account, then confirm (§11.15).
//
//  When no Firebase configuration is bundled this screen explains that sync is off and
//  the app carries on locally. That is a valid state, not an error: an apiary works
//  offline and account-free by design.
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var sync: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var confirmingDelete = false
    @State private var deletePassword = ""
    @State private var askingForPassword = false
    @State private var inviteCode: String?
    @State private var inviteError: String?
    @State private var joinCode = ""
    @State private var members: [SyncService.MemberDTO] = []
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ZStack {
                CombGround()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.section) {
                        switch auth.phase {
                        case .notConfigured: notConfigured
                        case .signedOut, .authenticating: signInForm
                        case .signedIn: signedIn
                        }
                    }
                    .padding(Space.screen)
                }
            }
            .task {
                guard auth.phase == .signedIn, let apiaryId = state.apiary?.id else { return }
                members = (try? await sync.members(apiaryId: apiaryId)) ?? []
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.accent)
                }
            }
        }
    }

    // MARK: Sync off

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            SectionHead(title: "Sync")
            Text("Everything works on this device")
                .font(Typo.displaySm)
                .foregroundStyle(Palette.textPrimary)
            Text(AuthService.explanation)
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NotePanel(text: "Your hives, the swarm clock, frame capture and the learned laying rate are all stored locally and none of it needs a signal.")
            localDataSection
        }
    }

    // MARK: Sign in

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            SectionHead(title: isSignUp ? "Create an account" : "Sign in")
            Text("An apiary is usually two people and always more than one season. Your inspections, and the laying rate this app learns for each queen, follow you — not this phone.")
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(Space.row)
                .combPanel(fill: Palette.surfaceElevated)

            SecureField("Password", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .padding(Space.row)
                .combPanel(fill: Palette.surfaceElevated)

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

            Button(isSignUp ? "Create account" : "Sign in") {
                isSignUp ? auth.signUp(email: email, password: password)
                         : auth.signIn(email: email, password: password)
            }
            .buttonStyle(HoneyButtonStyle())
            .disabled(email.isEmpty || password.count < 6 || auth.phase == .authenticating)

            Button(isSignUp ? "I already have an account" : "Create one instead") {
                isSignUp.toggle()
                auth.clearMessages()
            }
            .font(Typo.caption)
            .foregroundStyle(Palette.textSecondary)

            if !isSignUp {
                Button("Send a password reset") { auth.sendPasswordReset(email: email) }
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .disabled(email.isEmpty)
            }

            localDataSection
        }
    }

    // MARK: Signed in

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            VStack(alignment: .leading, spacing: Space.tight) {
                SectionHead(title: "Signed in")
                StatRow(label: "Email", value: auth.email ?? "—")
                if let apiary = state.apiary {
                    StatRow(label: "Apiary", value: apiary.name)
                    StatRow(label: "Members",
                            value: "\(max(1, members.count)) of \(InviteCodes.maxMembers)")
                }
                ForEach(members) { member in
                    StatRow(label: member.email,
                            value: member.role == "owner" ? "owner" : "member",
                            tint: member.id == auth.userId ? Palette.accent : Palette.textPrimary)
                }
            }
            .padding(Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .combPanel(fill: Palette.surfaceElevated)

            VStack(alignment: .leading, spacing: Space.tight) {
                SectionHead(title: "Share this apiary")
                Text("Up to four people can work the same apiary and see the same hive state at the hive.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let code = inviteCode {
                    // Код показывается ТОЛЬКО после ответа сервера: только он
                    // может поручиться, что код ещё никем не занят.
                    Text(code)
                        .font(Typo.display)
                        .tracking(4)
                        .foregroundStyle(Palette.accent)
                        .textSelection(.enabled)
                    Text("Valid for 7 days, works once.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }

                Button(busy ? "One moment…" : "Create an invite code") {
                    guard let apiaryId = state.apiary?.id else { return }
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            inviteCode = try await sync.createInvite(apiaryId: apiaryId)
                            inviteError = nil
                            Haptics.selection()
                        } catch {
                            inviteError = (error as? APIError)?.userMessage
                                ?? "Couldn’t create the code."
                        }
                    }
                }
                .buttonStyle(OutlineButtonStyle())
                .disabled(busy || state.apiary == nil)

                if let inviteError {
                    Text(inviteError)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.imminent)
                }
            }
            .padding(Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .combPanel(fill: Palette.surfaceElevated)

            joinSection
            syncSection

            Button("Sign out") {
                auth.signOut()
                sync.reset()
            }
            .buttonStyle(OutlineButtonStyle())

            deleteSection
        }
    }

    // MARK: Присоединиться к чужой пасеке

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Join another apiary")
            Text("If a partner sent you a code, enter it here. Your current hives stay on this device.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("CODE", text: $joinCode)
                    .textFieldStyle(.plain)
                    .font(Typo.figure)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onValueChange(of: joinCode) { value in
                        // Код читают вслух — приводим к виду сервера сразу,
                        // чтобы «abc123» и «ABC123» не были разными кодами.
                        let cleaned = value.uppercased()
                            .filter { InviteCodes.alphabet.contains($0) }
                        if cleaned != value { joinCode = String(cleaned.prefix(6)) }
                    }
                Button(busy ? "…" : "Join") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await sync.acceptInvite(code: joinCode)
                            joinCode = ""
                            inviteError = nil
                            await sync.sync(state: state)
                            await auth.refreshProfile()
                            if let apiaryId = state.apiary?.id {
                                members = (try? await sync.members(apiaryId: apiaryId)) ?? []
                            }
                            Haptics.swarmAverted()
                        } catch {
                            inviteError = (error as? APIError)?.userMessage
                                ?? "Couldn’t join."
                        }
                    }
                }
                .font(Typo.captionMed)
                .foregroundStyle(Palette.accent)
                .disabled(busy || joinCode.count != InviteCodes.length)
            }
            .padding(Space.row)
            .combPanel(fill: Palette.surfaceElevated)
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: Состояние синхронизации и конфликты

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Sync")

            switch sync.status {
            case .idle:
                Text("Not synced yet.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
            case .syncing:
                Text("Syncing…")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
            case .offline:
                // Не ошибка. Ровно то, ради чего приложение локальное.
                Text("No connection. Hives and the forecast work; changes sync later.")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text(message)
                    .font(Typo.caption).foregroundStyle(Palette.imminent)
                    .fixedSize(horizontal: false, vertical: true)
            case .done(let when):
                Text("Last sync: \(Fmt.day(when))")
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
            }

            if !sync.conflicts.isEmpty {
                // Слить два набора рамок автоматически нельзя — получился бы улей,
                // которого никто не видел вживую. Решает человек.
                Text("\(sync.conflicts.count) hive(s) differ — edited on two devices.")
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.watch)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(sync.conflicts, id: \.id) { conflict in
                    if let server = conflict.server {
                        HStack(spacing: Space.tight) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.name)
                                    .font(Typo.captionMed)
                                    .foregroundStyle(Palette.textPrimary)
                                Text("on server — version \(String(server.version ?? 0))")
                                    .font(Typo.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            Button("Take server’s") {
                                sync.resolveTakingServer(conflict, appState: state)
                                Haptics.selection()
                            }
                            .font(Typo.caption)
                            .foregroundStyle(Palette.accent)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button("Keep mine everywhere") {
                    sync.resolveKeepingLocal(appState: state)
                    Haptics.selection()
                }
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            }

            Button("Sync now") {
                Task { await sync.sync(state: state) }
            }
            .buttonStyle(OutlineButtonStyle())
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: Delete account — two taps (§11.15)

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Delete account")
            Text("Removes you from every apiary you belong to. If you are the last member of an apiary, that apiary and everything in it goes too. This cannot be undone.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Delete account") { confirmingDelete = true }
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.imminent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .combOutline(stroke: Palette.imminent)

            if let message = auth.errorMessage {
                Text(message)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.imminent)
            }
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
        .confirmationDialog("Delete your account?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { askingForPassword = true }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This removes you from every apiary and deletes everything stored on this device.")
        }
        .alert("Confirm it's you", isPresented: $askingForPassword) {
            SecureField("Password", text: $deletePassword)
            Button("Delete", role: .destructive) {
                auth.deleteAccount(password: deletePassword) { success in
                    if success {
                        state.wipeLocalData()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) { deletePassword = "" }
        } message: {
            Text("Signing in again is required before an account can be deleted.")
        }
    }

    // MARK: Local data — always available, account or not

    private var localDataSection: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Data on this device")
            Text("Hives, inspections, frame photographs and the weather cache are stored on this phone. Photographs never leave it.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Erase everything on this device") {
                confirmingDelete = false
                state.wipeLocalData()
                dismiss()
            }
            .font(Typo.captionMed)
            .foregroundStyle(Palette.imminent)
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }
}

// MARK: - Invite codes (§14)

enum InviteCodes {
    /// Six characters, excluding I, O, 0 and 1 so a code read aloud at an apiary gate
    /// cannot be mistyped.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 6
    static let maxMembers = 4

    static func generate() -> String {
        String((0..<length).map { _ in alphabet.randomElement() ?? "A" })
    }

    static func isValid(_ code: String) -> Bool {
        let upper = code.uppercased()
        return upper.count == length && upper.allSatisfy { alphabet.contains($0) }
    }
}
