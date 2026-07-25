import Foundation
import Testing
@testable import Asterias_Studio

@Suite("Settings")
struct SettingsTests {
    @Test func renderOptionsReadPersistedChoices() {
        let suiteName = "AsteriasTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("tinySquare", forKey: "selectedDimensions")
        defaults.set(3, forKey: "selectedLayerCount")
        defaults.set("userDefined", forKey: "selectedPalette")
        defaults.set(false, forKey: "isTilingEnabled")
        defaults.set("#112233", forKey: "customPaletteColor1")
        defaults.set("#445566", forKey: "customPaletteColor2")
        defaults.set("#778899", forKey: "customPaletteColor3")
        defaults.set("#AABBCC", forKey: "customPaletteColor4")
        defaults.set("#DDEEFF", forKey: "customPaletteColor5")
        defaults.set(false, forKey: AsteriasSettings.generatorSelectionKey(for: .julia))

        let options = AsteriasSettings.renderOptions(
            defaults: defaults,
            fallbackArea: AsteriasArea(width: 9, height: 7)
        )

        #expect(options.area.width == 64)
        #expect(options.area.height == 64)
        #expect(options.layerCount == 3)
        #expect(options.isTilingEnabled == false)
        #expect(options.palette.colors.count == 5)
        #expect(!options.allowedGenerators.contains(.julia))
        #expect(options.allowedGenerators.contains(.bubble))
    }

    @Test func unknownDimensionsUseFallbackArea() {
        let suiteName = "AsteriasTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unknown", forKey: "selectedDimensions")

        let options = AsteriasSettings.renderOptions(
            defaults: defaults,
            fallbackArea: AsteriasArea(width: 9, height: 7)
        )

        #expect(options.area.width == 9)
        #expect(options.area.height == 7)
    }
}
