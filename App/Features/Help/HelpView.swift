import SwiftUI

/// Explications pour ceux qui ne connaissent pas les formats, et informations sur l'app.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("L'univers EAGLE") {
                    topic(
                        "L'Aigle",
                        symbol: "crown.fill",
                        text: "Le numéro 1 du classement est l'Aigle. Le statut est calculé automatiquement : dès qu'un joueur passe devant, il devient le nouvel Aigle."
                    )
                    topic(
                        "Defend your crown",
                        symbol: "shield.lefthalf.filled",
                        text: "La carte de l'Aigle indique depuis combien de tours il tient la première place."
                    )
                    topic(
                        "Hunt the Eagle · Rise above",
                        symbol: "arrow.up.right",
                        text: "Chaque joueur voit son retard en points sur l'Aigle et les places gagnées ou perdues au dernier tour."
                    )
                    topic(
                        "Hall of Eagles",
                        symbol: "trophy.fill",
                        text: "Les tournois terminés gardent la trace de leur Aigle, sur l'écran d'accueil."
                    )
                }

                Section("Les formats") {
                    topic(
                        "Americano",
                        symbol: "arrow.triangle.swap",
                        text: "Matchs en double, 2 contre 2. Les partenaires changent à chaque tour pour que chacun joue avec le plus de monde possible. Chaque joueur marque les points de son équipe : en 24 points, si votre équipe gagne 15–9, vous marquez 15 points et vos adversaires 9 chacun."
                    )
                    topic(
                        "Mexicano",
                        symbol: "chart.bar.xaxis",
                        text: "Le premier tour est tiré au sort (ou selon le niveau). Ensuite, après chaque tour, les joueurs proches au classement sont regroupés : le 1er joue avec le 4e contre le 2e et le 3e, et ainsi de suite. Les matchs restent serrés du début à la fin."
                    )
                }

                Section("Les points") {
                    topic(
                        "Total fixe (16, 21, 24, 32…)",
                        symbol: "sum",
                        text: "On joue un nombre de points fixe, peu importe qui les gagne. En 21 points, un match se termine par exemple 12–9. Saisissez le score d'une équipe : l'autre est calculé."
                    )
                    topic(
                        "Premier à N",
                        symbol: "flag.checkered",
                        text: "La première équipe à atteindre N points gagne. Saisissez le score du perdant."
                    )
                    topic(
                        "Libre (au temps)",
                        symbol: "timer",
                        text: "Pour les matchs joués sur une durée : saisissez les points de chaque équipe à la fin."
                    )
                }

                Section("Pendant le tournoi") {
                    topic(
                        "Pauses",
                        symbol: "cup.and.saucer",
                        text: "Si le nombre de joueurs n'est pas un multiple de 4, certains font une pause à chaque tour, à tour de rôle. L'app répartit les pauses équitablement."
                    )
                    topic(
                        "Tours libres",
                        symbol: "infinity",
                        text: "Vous ne savez pas combien de tours vous aurez le temps de jouer ? Activez « Tours libres » : chaque tour est généré quand le précédent est terminé, et vous arrêtez quand vous voulez."
                    )
                    topic(
                        "Corriger une erreur",
                        symbol: "pencil",
                        text: "Touchez le match, puis « Corriger le score ». L'ancien score est conservé dans l'historique et le classement se met à jour."
                    )
                }

                Section("Le classement") {
                    topic(
                        "Ordre",
                        symbol: "list.number",
                        text: "1. Points marqués. 2. Victoires. 3. Différence de points. Sinon, les joueurs sont ex aequo et partagent la même place (signalée par « = »)."
                    )
                }

                Section("Partage entre amis") {
                    topic(
                        "Suivre un tournoi",
                        symbol: "person.2.wave.2",
                        text: "L'organisateur partage un code à 6 caractères. Les amis le saisissent dans « Rejoindre un tournoi » et suivent les scores et le classement. Seul l'organisateur saisit les scores."
                    )
                }

                Section("Confidentialité") {
                    topic(
                        "Vos données",
                        symbol: "lock",
                        text: "Pas de compte, pas de publicité, aucun suivi. Les tournois sont enregistrés sur votre iPhone. Un tournoi n'est envoyé en ligne que si vous le partagez, et vous pouvez le retirer à tout moment."
                    )
                    if let url = AppLinks.privacyPolicy {
                        Link(destination: url) {
                            Label("Politique de confidentialité", systemImage: "doc.text")
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: AppInfo.version)
                } footer: {
                    Text("EAGLE — Own the court. Gratuit, sans publicité ni abonnement.")
                }
            }
            .eagleScreenBackground()
            .navigationTitle("Comment ça marche ?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func topic(_ title: LocalizedStringKey, symbol: String, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}

#Preview {
    HelpView()
}
