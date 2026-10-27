import PadelCore
import SwiftUI

/// Rejoindre le tournoi d'un ami avec son code d'invitation (ou un lien padelbuddy://join/…).
struct JoinTournamentView: View {
    var initialCode: String = ""
    var onJoined: (Tournament.ID) -> Void = { _ in }

    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var failure: SyncFailure?
    @FocusState private var isFieldFocused: Bool

    private var inviteCode: InviteCode? { InviteCode(code) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Saisissez le code reçu de l'organisateur.")
                        .font(.headline)

                    TextField("Ex. : K7M2QP", text: $code)
                        .font(.system(.title, design: .monospaced, weight: .bold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .focused($isFieldFocused)
                        .submitLabel(.join)
                        .onSubmit(join)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .fill(Theme.card)
                        )
                        .onChange(of: code) { _, newValue in
                            let cleaned = InviteCode.clean(newValue)
                            if cleaned != newValue { code = cleaned }
                            failure = nil
                        }
                        .accessibilityLabel("Code d'invitation")

                    if let failure {
                        Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.warning)
                    }

                    if !sync.isConfigured {
                        info("Le partage entre iPhone n'est pas encore activé dans cette version de l'app. Il le sera dans la version publiée.")
                    } else {
                        info("Vous suivrez les matchs, les scores et le classement en lecture seule. C'est l'organisateur qui valide les scores. Mise à jour toutes les 20 secondes environ, sans garantie de temps réel.")
                        info("Aucun compte n'est nécessaire. Une connexion est requise pour rejoindre ; ensuite le tournoi reste consultable hors ligne.")
                    }

                    Button(action: join) {
                        if isJoining {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Label("Rejoindre", systemImage: "arrow.right.circle.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(inviteCode == nil || isJoining || !sync.isConfigured)
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Rejoindre un tournoi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear {
                if code.isEmpty { code = InviteCode.clean(initialCode) }
                if InviteCode(code) != nil, sync.isConfigured {
                    join()
                } else {
                    isFieldFocused = true
                }
            }
        }
    }

    private func info(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func join() {
        guard let inviteCode, !isJoining else { return }
        isJoining = true
        failure = nil
        Task {
            do {
                let id = try await sync.join(code: inviteCode)
                dismiss()
                onJoined(id)
            } catch {
                failure = SyncCoordinator.failure(error)
            }
            isJoining = false
        }
    }
}
