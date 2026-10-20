import PadelCore
import SwiftUI

/// Partage d'un tournoi par l'organisateur : publication, code d'invitation, message à envoyer.
struct ShareTournamentView: View {
    let tournamentID: Tournament.ID

    @Environment(TournamentLibrary.self) private var library
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var failure: SyncFailure?
    @State private var isConfirmingUnpublish = false

    private var tournament: Tournament? { library.tournament(id: tournamentID) }
    private var code: InviteCode? { tournament?.sharing.flatMap { InviteCode($0.code) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let tournament {
                        if let code {
                            sharedContent(tournament, code: code)
                        } else {
                            notSharedContent
                        }
                    }
                    if let failure {
                        Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.warning)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Partager le tournoi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    // MARK: - Pas encore partagé

    private var notSharedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vos amis suivent les matchs, les scores et le classement sur leur iPhone.")
                .font(.headline)
            point("person.badge.shield.checkmark", "Vous restez seul à saisir et valider les scores. Les autres consultent en lecture seule.")
            point("number.square", "Le tournoi est publié en ligne avec un code à 6 caractères. Toute personne qui a le code peut le consulter (noms des joueurs et scores).")
            point("clock.arrow.circlepath", "Les mises à jour arrivent en général en quelques secondes, sans garantie de temps réel. Sans réseau, vos scores restent sur cet iPhone et partent au retour de la connexion.")
            point("icloud", "Publier nécessite d'être connecté à iCloud. Suivre un tournoi ne nécessite aucun compte.")
            point("xmark.bin", "Vous pouvez retirer le tournoi du partage à tout moment.")

            if !sync.isConfigured {
                Label("Le partage entre iPhone n'est pas encore activé dans cette version de l'app.", systemImage: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            }

            Button(action: share) {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Label("Publier et obtenir un code", systemImage: "icloud.and.arrow.up")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking || !sync.isConfigured)
        }
    }

    // MARK: - Partagé

    private func sharedContent(_ tournament: Tournament, code: InviteCode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 6) {
                Text("Code d'invitation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: code.formatted)
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel(code.value.map(String.init).joined(separator: " "))
            }
            .frame(maxWidth: .infinity)
            .cardStyle()

            ShareLink(item: invitation(tournament, code: code)) {
                Label("Envoyer l'invitation", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())

            SyncStatusLabel(status: sync.status(of: tournament.id), tournament: tournament)

            if SyncRules.needsPublish(tournament) {
                Button("Envoyer maintenant") { share() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isWorking)
            }

            Text("Vos amis ouvrent le lien, ou saisissent le code dans « Rejoindre un tournoi ». S'ils n'ont pas encore l'app, le message leur indique comment l'obtenir.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Retirer du partage", role: .destructive) {
                isConfirmingUnpublish = true
            }
            .frame(maxWidth: .infinity)
            .disabled(isWorking)
            .confirmationDialog("Retirer du partage ?", isPresented: $isConfirmingUnpublish, titleVisibility: .visible) {
                Button("Retirer", role: .destructive, action: unpublish)
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La version en ligne sera supprimée et le code ne fonctionnera plus. Le tournoi reste sur cet iPhone ; les copies déjà ouvertes par vos amis ne seront plus mises à jour.")
            }
        }
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.green)
        }
        .font(.subheadline)
    }

    /// Message d'invitation, avec solution de repli pour ceux qui n'ont pas l'app.
    private func invitation(_ tournament: Tournament, code: InviteCode) -> String {
        var lines = [
            String(localized: "🎾 Rejoins le tournoi « \(tournament.name) » sur Padel Buddy"),
            String(localized: "Code : \(code.formatted)"),
            String(localized: "Ouvrir dans l'app : \(code.appURL.absoluteString)"),
        ]
        if let download = AppLinks.download {
            lines.append(String(localized: "Pas encore l'app ? Télécharge-la gratuitement : \(download.absoluteString)"))
        } else {
            lines.append(String(localized: "Pas encore l'app ? Demande-moi le lien pour l'installer, puis saisis le code dans « Rejoindre un tournoi »."))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Actions

    private func share() {
        isWorking = true
        failure = nil
        Task {
            do {
                try await sync.share(tournamentID)
            } catch {
                failure = SyncCoordinator.failure(error)
            }
            isWorking = false
        }
    }

    private func unpublish() {
        isWorking = true
        failure = nil
        Task {
            do {
                try await sync.unpublish(tournamentID)
            } catch {
                failure = SyncCoordinator.failure(error)
            }
            isWorking = false
        }
    }
}

/// État de synchronisation, en clair.
struct SyncStatusLabel: View {
    let status: SyncCoordinator.Status
    let tournament: Tournament

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var lastSync: Date? {
        if case .upToDate(let date) = status { return date }
        return tournament.sharing?.lastSyncedAt
    }

    private var text: String {
        switch status {
        case .syncing:
            return String(localized: "Synchronisation…")
        case .pending(let failure):
            if failure == .offline {
                return String(localized: "Hors ligne : modifications enregistrées sur cet iPhone, envoi au retour du réseau.")
            }
            return String(localized: "Modifications en attente d'envoi.")
        case .failed(let failure):
            return failure.message
        case .unpublished:
            return String(localized: "L'organisateur a retiré ce tournoi du partage. Dernière version conservée sur cet iPhone.")
        case .idle, .upToDate:
            if let lastSync {
                let relative = lastSync.formatted(.relative(presentation: .named))
                return String(localized: "Mis à jour \(relative).")
            }
            return String(localized: "Pas encore synchronisé.")
        }
    }

    private var symbol: String {
        switch status {
        case .syncing: "arrow.triangle.2.circlepath"
        case .pending: "icloud.slash"
        case .failed, .unpublished: "exclamationmark.icloud"
        case .idle, .upToDate: "checkmark.icloud"
        }
    }

    private var color: Color {
        switch status {
        case .failed, .unpublished, .pending: Theme.warning
        default: Theme.green
        }
    }
}
