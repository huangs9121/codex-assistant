import CoreGraphics
import CodexQuotaCore
import Foundation

struct ModifierTapGesture: Equatable {
    static let keyCodesDefaultsKey = "modifierTapGestureKeyCodes"
    static let tapCountDefaultsKey = "modifierTapGestureTapCount"
    static let defaultKeyCodes: Set<CGKeyCode> = [54, 55]
    static let defaultTapCount = 2
    static let supportedKeyCodes: Set<CGKeyCode> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    let keyCodes: Set<CGKeyCode>
    let tapCount: Int

    init(keyCodes: Set<CGKeyCode>, tapCount: Int) {
        self.keyCodes = keyCodes
        self.tapCount = tapCount
    }

    init(defaults: UserDefaults) {
        let rawKeyCodes = defaults.array(forKey: Self.keyCodesDefaultsKey)?
            .compactMap { $0 as? Int } ?? []
        let keyCodes = Set(rawKeyCodes.compactMap { UInt16(exactly: $0) })
        let tapCount = defaults.object(forKey: Self.tapCountDefaultsKey) as? Int

        if !rawKeyCodes.isEmpty,
           keyCodes.count == rawKeyCodes.count,
           Self.supportedKeyCodes.isSuperset(of: keyCodes),
           let tapCount,
           (1...2).contains(tapCount) {
            self.init(keyCodes: keyCodes, tapCount: tapCount)
        } else {
            self.init(keyCodes: Self.defaultKeyCodes, tapCount: Self.defaultTapCount)
        }
    }

    var sequenceConfiguration: ModifierTapSequence.Configuration {
        ModifierTapSequence.Configuration(
            keyCodes: keyCodes,
            requiredTapCount: tapCount
        )
    }

    func displayString(text: AppText) -> String {
        text.modifierTapGestureDisplay(keyCodes: keyCodes, tapCount: tapCount)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(keyCodes.map(Int.init).sorted(), forKey: Self.keyCodesDefaultsKey)
        defaults.set(tapCount, forKey: Self.tapCountDefaultsKey)
    }

    static func isSupported(keyCode: CGKeyCode) -> Bool {
        supportedKeyCodes.contains(keyCode)
    }

    static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
        switch keyCode {
        case 54, 55:
            .maskCommand
        case 56, 60:
            .maskShift
        case 58, 61:
            .maskAlternate
        case 59, 62:
            .maskControl
        case 57:
            .maskAlphaShift
        case 63:
            .maskSecondaryFn
        default:
            nil
        }
    }

    static func allModifierFlags() -> CGEventFlags {
        [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn, .maskAlphaShift]
    }
}
