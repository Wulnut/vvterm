import Foundation

enum TerminalHardwareTextInputRoutingPolicy {
    static func shouldRoutePressToSystemTextInput(
        hasControlModifier: Bool,
        hasAlternateModifier: Bool,
        hasCommandModifier: Bool,
        hasActiveIMEComposition: Bool,
        isSystemTextInputToggleKey: Bool,
        hasTerminalFallbackKey: Bool,
        keyProducesText: Bool
    ) -> Bool {
        if hasControlModifier || hasAlternateModifier || hasCommandModifier {
            return false
        }
        if hasActiveIMEComposition {
            return true
        }
        if isSystemTextInputToggleKey {
            return true
        }
        if hasTerminalFallbackKey {
            return false
        }
        // Let UIKit own all remaining unmodified hardware text input so IMEs,
        // dead keys, and layout-specific composition can start reliably.
        let _ = keyProducesText
        return true
    }
}
