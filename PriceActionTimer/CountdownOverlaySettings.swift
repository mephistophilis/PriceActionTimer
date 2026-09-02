//
//  CountdownOverlaySettings.swift
//  PriceActionTimer
//

import Combine
import Foundation

enum CountdownCorner: String, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft:
            return "Top Left"
        case .topRight:
            return "Top Right"
        case .bottomLeft:
            return "Bottom Left"
        case .bottomRight:
            return "Bottom Right"
        }
    }
}

@MainActor
final class CountdownOverlaySettings: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.isEnabledKey)
        }
    }

    @Published var corner: CountdownCorner {
        didSet {
            userDefaults.set(corner.rawValue, forKey: Self.cornerKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let isEnabledKey = "com.m.PriceActionTimer.overlay.isEnabled"
    private static let cornerKey = "com.m.PriceActionTimer.overlay.corner"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedIsEnabled = userDefaults.object(forKey: Self.isEnabledKey) == nil
            ? true
            : userDefaults.bool(forKey: Self.isEnabledKey)
        let storedCorner = userDefaults.string(forKey: Self.cornerKey)
            .flatMap(CountdownCorner.init(rawValue:))
            ?? .bottomRight

        self.isEnabled = storedIsEnabled
        self.corner = storedCorner
    }
}
