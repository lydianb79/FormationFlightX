// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FormationFlightX",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "FormationFlightX", path: "Sources/FormationFlightX")
    ]
)
