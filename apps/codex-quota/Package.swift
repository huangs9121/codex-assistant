// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
        .library(name: "CodexQuotaUI", targets: ["CodexQuotaUI"]),
        .executable(name: "CodexQuotaApp", targets: ["CodexQuotaApp"])
    ],
    targets: [
        .target(name: "CodexQuotaCore"),
        .target(
            name: "CodexQuotaUI",
            dependencies: ["CodexQuotaCore"]
        ),
        .executableTarget(
            name: "CodexQuotaApp",
            dependencies: ["CodexQuotaCore", "CodexQuotaUI"]
        ),
        .executableTarget(
            name: "CodexQuotaCoreTests",
            dependencies: ["CodexQuotaCore", "CodexQuotaUI"],
            path: "Tests/CodexQuotaCoreTests"
        )
    ]
)
