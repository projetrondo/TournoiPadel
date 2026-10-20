import SwiftUI

/// Rejoindre le tournoi d'un ami avec son code d'invitation.
/// La récupération en ligne arrive avec la synchronisation (phase 6) : l'écran explique le
/// fonctionnement mais ne prétend pas rejoindre un tournoi.
struct JoinTournamentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    static let codeLength = 6

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Saisissez le code reçu de l'organisateur.")
                    .font(.headline)

                TextField("Ex. : K7M2QP", text: $code)
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .fill(Theme.card)
                    )
                    .onChange(of: code) { _, newValue in
                        let cleaned = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(Self.codeLength))
                        if cleaned != newValue { code = cleaned }
                    }

                Label {
                    Text("Le partage de tournois entre iPhone arrive dans une prochaine version. Vous pourrez alors suivre les matchs et le classement de vos amis.")
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.green)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()

                Button {} label: {
                    Label("Rejoindre", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
            }
            .padding(16)
            .background(Theme.background)
            .navigationTitle("Rejoindre un tournoi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    JoinTournamentView()
}
