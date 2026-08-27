// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RadarMap",
    platforms: [
        .watchOS(.v10),
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RadarMap",
            targets: ["RadarMap"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RadarMap",
            path: "RadarMap",
            exclude: [
                "Resources/Info.plist",
                "Resources/GoogleService-Info.plist",
                "Resources/RadarMap.storekit"
            ]
        ),
        .testTarget(
            name: "RadarMapTests",
            dependencies: ["RadarMap"],
            path: "RadarMapTests"
        ),
    ]
)
