import PhotosUI
import SwiftUI

/// Réglages de l'app : fond d'écran, aide.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppBackground.storageKey) private var background = AppBackground.carbon.rawValue
    @AppStorage(AppBackground.photoVersionKey) private var photoVersion = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isShowingHelp = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fond d'écran")
                            .eagleSectionTitle()
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(AppBackground.presets) { option in
                                Button {
                                    background = option.rawValue
                                } label: {
                                    tile(option)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                                .accessibilityAddTraits(background == option.rawValue ? [.isSelected] : [])
                            }
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                tile(.photo)
                                    .overlay {
                                        if isLoadingPhoto { ProgressView().tint(Theme.accent) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppBackground.photo.title)
                            .accessibilityAddTraits(background == AppBackground.photo.rawValue ? [.isSelected] : [])
                        }
                        Text("« Ma photo » : choisissez une image de votre photothèque. Elle est assombrie pour que le texte reste lisible, et reste sur cet iPhone.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
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
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                loadPhoto(item)
            }
            .alert(
                "Erreur",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    /// Vignette d'un fond : aperçu réduit, nom, bordure dorée si choisi.
    private func tile(_ option: AppBackground) -> some View {
        let isSelected = background == option.rawValue
        let hasPhoto = FileManager.default.fileExists(atPath: AppBackground.photoURL.path)
        return VStack(spacing: 6) {
            ZStack {
                if option == .photo, !hasPhoto {
                    Theme.card
                    Image(systemName: "photo.badge.plus")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                } else {
                    EagleBackgroundView(preview: option)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.stroke), lineWidth: isSelected ? 2.5 : 1)
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

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer {
                isLoadingPhoto = false
                photoItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadNoSuchFile) }
                try AppBackground.savePhoto(data)
                photoVersion += 1
                background = AppBackground.photo.rawValue
            } catch {
                errorMessage = String(localized: "Cette photo n'a pas pu être utilisée. Essayez-en une autre.", bundle: .appLanguage)
            }
        }
    }
}
