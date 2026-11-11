import PhotosUI
import SwiftUI
import UIKit

/// Fond d'écran de l'app, choisi dans les réglages : fonds EAGLE prédéfinis ou photo personnelle.
enum AppBackground: String, CaseIterable, Identifiable, Sendable {
    case carbon
    case night
    case court
    case gold
    case clay
    case photo

    static let storageKey = "eagle.background"
    /// Change à chaque nouvelle photo choisie (pour recharger l'image).
    static let photoVersionKey = "eagle.background.photoVersion"

    var id: String { rawValue }

    /// Fonds proposés en vignettes (la photo a sa propre case).
    static var presets: [AppBackground] { allCases.filter { $0 != .photo } }

    var title: String {
        switch self {
        case .carbon: String(localized: "Carbone", bundle: .appLanguage)
        case .night: String(localized: "Nuit", bundle: .appLanguage)
        case .court: String(localized: "Court", bundle: .appLanguage)
        case .gold: String(localized: "Or", bundle: .appLanguage)
        case .clay: String(localized: "Terre battue", bundle: .appLanguage)
        case .photo: String(localized: "Ma photo", bundle: .appLanguage)
        }
    }

    /// Photo personnelle, assombrie à l'affichage pour garder le texte lisible.
    static var photoURL: URL {
        URL.applicationSupportDirectory.appending(path: "background.jpg")
    }

    /// Enregistre la photo choisie, réduite (2000 px au plus) et compressée.
    static func savePhoto(_ data: Data) throws {
        guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let maxSide: CGFloat = 2000
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try jpeg.write(to: photoURL, options: .atomic)
    }
}

/// Le fond choisi, en plein écran.
struct EagleBackgroundView: View {
    @AppStorage(AppBackground.storageKey) private var stored = AppBackground.carbon.rawValue
    @AppStorage(AppBackground.photoVersionKey) private var photoVersion = 0
    /// Aperçu d'un fond précis (vignettes des réglages) au lieu du fond choisi.
    var preview: AppBackground?

    var body: some View {
        let background = preview ?? AppBackground(rawValue: stored) ?? .carbon
        ZStack {
            Theme.carbon
            switch background {
            case .carbon:
                EmptyView()
            case .night:
                LinearGradient(colors: [Color(hex: 0x111A2E), Color(hex: 0x0B0D10)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0x2A4A8A).opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 500)
            case .court:
                LinearGradient(colors: [Color(hex: 0x0E2A1E), Color(hex: 0x0B1410)], startPoint: .top, endPoint: .bottom)
                CourtLines()
                    .stroke(Color.white.opacity(0.07), lineWidth: 2)
            case .gold:
                RadialGradient(colors: [Theme.gold.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 520)
                RadialGradient(colors: [Theme.goldDeep.opacity(0.18), .clear], center: .bottomLeading, startRadius: 0, endRadius: 420)
            case .clay:
                LinearGradient(colors: [Color(hex: 0x3A1A0E), Color(hex: 0x140C09)], startPoint: .top, endPoint: .bottom)
                CourtLines()
                    .stroke(Color.white.opacity(0.06), lineWidth: 2)
            case .photo:
                if let image = PhotoCache.image(version: photoVersion) {
                    GeometryReader { proxy in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                    // Voile sombre : le texte et les cartes restent lisibles sur n'importe quelle photo.
                    LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lignes d'un terrain de padel vues de haut, en filigrane.
private struct CourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let court = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.06)
        path.addRect(court)
        // Filet, lignes de service et ligne centrale.
        path.move(to: CGPoint(x: court.minX, y: court.midY))
        path.addLine(to: CGPoint(x: court.maxX, y: court.midY))
        let service = court.height * 0.15
        for y in [court.midY - service * 2, court.midY + service * 2] {
            path.move(to: CGPoint(x: court.minX, y: y))
            path.addLine(to: CGPoint(x: court.maxX, y: y))
        }
        path.move(to: CGPoint(x: court.midX, y: court.midY - service * 2))
        path.addLine(to: CGPoint(x: court.midX, y: court.midY + service * 2))
        return path
    }
}

/// Garde la photo de fond en mémoire : elle n'est relue sur disque qu'après un changement.
@MainActor
private enum PhotoCache {
    private static var cached: (version: Int, image: UIImage?)?

    static func image(version: Int) -> UIImage? {
        if let cached, cached.version == version { return cached.image }
        let image = UIImage(contentsOfFile: AppBackground.photoURL.path)
        cached = (version, image)
        return image
    }
}

extension View {
    /// Fond d'écran choisi dans les réglages, sous tout l'écran.
    func eagleBackground() -> some View {
        background { EagleBackgroundView().ignoresSafeArea() }
    }
}
