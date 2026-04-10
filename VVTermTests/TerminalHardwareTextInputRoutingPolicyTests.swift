import Testing
@testable import VVTerm

struct TerminalHardwareTextInputRoutingPolicyTests {
    @Test
    func routesPrintablePinyinKeysToSystemTextInput() {
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: false,
                hasCommandModifier: false,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: false,
                keyProducesText: true
            )
        )
    }

    @Test
    func routesPrintableKanaKeysToSystemTextInput() {
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: false,
                hasCommandModifier: false,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: false,
                keyProducesText: true
            )
        )
    }

    @Test
    func routesPrintableHangulKeysToSystemTextInput() {
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: false,
                hasCommandModifier: false,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: false,
                keyProducesText: true
            )
        )
    }

    @Test
    func routesLatinPrintableKeysToSystemTextInput() {
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: false,
                hasCommandModifier: false,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: false,
                keyProducesText: true
            )
        )
    }

    @Test
    func keepsTerminalFallbackKeysOffSystemTextInputEvenInCJKLayouts() {
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: false,
                hasCommandModifier: false,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: true,
                keyProducesText: true
            ) == false
        )
    }

    @Test
    func routesCapsLockToggleToSystemTextInputEvenThoughItIsFallbackKey() {
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: false,
                hasCommandModifier: false,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: true,
                hasTerminalFallbackKey: true,
                keyProducesText: false
            )
        )
    }

    @Test
    func alwaysRoutesActiveCompositionThroughSystemTextInput() {
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: false,
                hasCommandModifier: false,
                hasActiveIMEComposition: true,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: true,
                keyProducesText: false
            )
        )
    }

    @Test
    func keepsModifiedPrintableKeysOnDirectGhosttyPath() {
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: true,
                hasAlternateModifier: false,
                hasCommandModifier: false,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: false,
                keyProducesText: true
            ) == false
        )
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: true,
                hasCommandModifier: false,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: false,
                keyProducesText: true
            ) == false
        )
        #expect(
            TerminalHardwareTextInputRoutingPolicy.shouldRoutePressToSystemTextInput(
                hasControlModifier: false,
                hasAlternateModifier: false,
                hasCommandModifier: true,
                hasActiveIMEComposition: false,
                isSystemTextInputToggleKey: false,
                hasTerminalFallbackKey: false,
                keyProducesText: true
            ) == false
        )
    }
}
