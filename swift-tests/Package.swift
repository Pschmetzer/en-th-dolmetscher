// swift-tools-version:5.9
// Echte Swift-Tests für die reinen Logikdateien der Mac-App (app/*Logic.swift). Die App selbst baut ./build.sh
// per swiftc; dieses Paket verlinkt nur die Dateien ohne UI-/Engine-Abhängigkeit (Symlinks in Sources/).
// Aufruf: cd swift-tests && swift test
import PackageDescription

let package = Package(
    name: "DolmetscherLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DolmetscherLogic"),
        .testTarget(name: "DolmetscherLogicTests", dependencies: ["DolmetscherLogic"]),
    ]
)
