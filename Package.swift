// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MP4Merger",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MP4Merger", targets: ["MP4Merger"])
    ],
    targets: [
        .executableTarget(
            name: "MP4Merger",
            path: "Sources/MP4Merger"
        )
    ]
)
//
//  Package.swift
//  MP4Merger
//
//  Created by (redacted) on 2026/05/17.
//

