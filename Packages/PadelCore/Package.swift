// swift-tools-version: 6.0
import PackageDescription

// Moteur de Padel Buddy : modèle, règles, génération des matchs, classement, persistance.
// Dépend uniquement de Foundation pour rester testable sur macOS comme sur Linux.
let package = Package(
    name: "PadelCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PadelCore", targets: ["PadelCore"])
    ],
    targets: [
        .target(name: "PadelCore"),
        .testTarget(name: "PadelCoreTests", dependencies: ["PadelCore"])
    ]
)
