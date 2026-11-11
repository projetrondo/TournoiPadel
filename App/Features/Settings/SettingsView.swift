import SwiftUI

/// Réglages de l'app : fond d'écran, aide.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppBackground.storageKey) private var background = AppBackground.carbon.rawValue
    @State private var isShowingHelp = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fond d'écran")
                            .eagleSectionTitle()
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(AppBackground.allCases) { option in
                                Button {
                                    background = option.rawValue
                                } label: {
                                    BackgroundTile(option: option, isSelected: background == option.rawValue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                                .accessibilityAddTraits(background == option.rawValue ? [.isSelected] : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Aide")
                            .eagleSectionTitle()
                        Button {
                            isShowingHelp = true
                        } label: {
                            HStack {
                                Label("Comment ça marche ?", systemImage: "questionmark.circle")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .cardStyle()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .eagleBackground()
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingHelp) {
                HelpView()
            }
        }
    }
}

/// Vignette d'un fond : aperçu réduit, nom, bordure dorée si choisi.
private struct BackgroundTile: View {
    let option: AppBackground
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(option.color)
                .frame(height: 76)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.primary.opacity(0.25)), lineWidth: isSelected ? 2.5 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.gold)
                            .padding(6)
                    }
                }
            Text(option.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.gold : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
