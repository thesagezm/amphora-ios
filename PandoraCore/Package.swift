// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PandoraCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "PandoraCore", targets: ["PandoraCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "PandoraCore",
            dependencies: [
                .product(name: "CryptoSwift", package: "CryptoSwift")
            ]
        ),
        .testTarget(
            name: "PandoraCoreTests",
            dependencies: ["PandoraCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
