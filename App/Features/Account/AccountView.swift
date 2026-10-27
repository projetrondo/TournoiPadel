import AuthenticationServices
import PadelCore
import SwiftUI

/// Compte EAGLE : connexion Google ou Apple, état de la sauvegarde, déconnexion, suppression.
struct AccountView: View {
    @Environment(AccountCenter.self) private var accounts
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let account = accounts.account {
                        signedIn(account)
                    } else {
                        signedOut
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Mon compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .task { await accounts.loadProviders() }
            .alert(
                "Compte",
                isPresented: Binding(get: { accounts.errorMessage != nil }, set: { if !$0 { accounts.errorMessage = nil } }),
                presenting: accounts.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: - Non connecté

    private var signedOut: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                GoldEagle(size: 64)
                Text("Garde tes tournois en sécurité")
                    .font(Theme.display(.title2, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                benefit("icloud.and.arrow.up.fill", "Sessions, joueurs et tournois sauvegardés automatiquement.")
                benefit("iphone.gen3", "Tout est retrouvé sur un nouvel iPhone, en te connectant.")
                benefit("wifi.slash", "Sans compte ou sans réseau, l'app fonctionne exactement pareil.")
            }
            .cardStyle()

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = accounts.appleNonceHash()
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                if accounts.providers?.google ?? true {
                    Button(action: signInWithGoogle) {
                        HStack(spacing: 10) {
                            Text(verbatim: "G")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: 0x4285F4))
                            Text("Continuer avec Google")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Continuer avec Google")
                }
            }
            .disabled(accounts.isWorking)
            .overlay {
                if accounts.isWorking { ProgressView().tint(Theme.accent) }
            }

            Text("Nous enregistrons ton identifiant de connexion, ton prénom et ton adresse (si Google ou Apple la transmettent), et le contenu de tes sessions et tournois. Rien d'autre, pas de publicité.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func benefit(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signInWithGoogle() {
        Task {
            guard let url = await accounts.googleSignInURL() else { return }
            do {
                let callback = try await webAuthenticationSession.authenticate(
                    using: url,
                    callbackURLScheme: "eagle",
                    preferredBrowserSession: .ephemeral
                )
                await accounts.completeGoogleSignIn(callback: callback)
            } catch {
                // Fenêtre fermée par l'utilisateur : rien à signaler.
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            Task {
                await accounts.completeAppleSignIn(identityToken: credential.identityToken, givenName: credential.fullName?.givenName)
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                accounts.errorMessage = String(localized: "La connexion avec Apple a échoué. Réessayez.")
            }
        }
    }

    // MARK: - Connecté

    private func signedIn(_ account: AccountInfo) -> some View {
        let name = account.displayName ?? account.email ?? String(localized: "Joueur EAGLE")
        return VStack(spacing: 20) {
            VStack(spacing: 8) {
                PlayerAvatar(name: name, tier: .eagle, size: 88)
                Text(name)
                    .font(Theme.display(.title, weight: .black))
                    .foregroundStyle(Theme.ink)
                if let email = account.email, email != name {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                if let provider = account.providers.first {
                    BadgeView(text: provider == "apple" ? String(localized: "Connecté avec Apple") : String(localized: "Connecté avec Google"), color: Theme.secondaryText)
                }
            }
            .padding(.top, 8)

            HStack(spacing: 14) {
                Image(systemName: accounts.isBackingUp ? "arrow.triangle.2.circlepath" : "checkmark.icloud.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: accounts.isBackingUp)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sauvegarde automatique")
                        .font(Theme.display(.headline, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.ink)
                    Text(backupStatus)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .cardStyle()

            VStack(spacing: 10) {
                Button {
                    Task { await accounts.backUp() }
                } label: {
                    Label("Sauvegarder maintenant", systemImage: "icloud.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(accounts.isBackingUp)

                Button {
                    isConfirmingSignOut = true
                } label: {
                    Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Button("Supprimer mon compte", role: .destructive) {
                isConfirmingDelete = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.error)
            .frame(minHeight: 44)
        }
        .disabled(accounts.isWorking)
        .confirmationDialog("Se déconnecter ?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { Task { await accounts.signOut() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes sessions et tournois restent sur cet iPhone. La sauvegarde s'arrête jusqu'à la prochaine connexion.")
        }
        .confirmationDialog("Supprimer ton compte ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer le compte et la sauvegarde", role: .destructive) { Task { await accounts.deleteAccount() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le compte et toute la sauvegarde en ligne sont effacés définitivement. Les sessions et tournois présents sur cet iPhone sont conservés.")
        }
    }

    private var backupStatus: String {
        if accounts.isBackingUp { return String(localized: "Sauvegarde en cours…") }
        guard let date = accounts.lastBackupAt else { return String(localized: "Première sauvegarde à la prochaine modification.") }
        return String(localized: "Dernière sauvegarde \(date.formatted(.relative(presentation: .named)))")
    }
}
