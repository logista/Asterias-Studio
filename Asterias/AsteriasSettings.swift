import Foundation

/// Reads persisted UI choices and converts them into render options.
struct AsteriasSettings: Sendable {
    static let suiteName = "com.asterias.settings"
    static let defaults = UserDefaults(suiteName: suiteName) ?? .standard

    static func renderOptions(defaults: UserDefaults = AsteriasSettings.defaults, fallbackArea: AsteriasArea) -> AsteriasRenderOptions {
        AsteriasRenderOptions(
            area: area(defaults: defaults, fallbackArea: fallbackArea),
            layerCount: layerCount(defaults: defaults),
            palette: palette(defaults: defaults),
            isTilingEnabled: defaults.object(forKey: "isTilingEnabled") as? Bool ?? true,
            allowedGenerators: allowedGenerators(defaults: defaults),
            seed: nil
        )
    }

    /// Unknown dimension strings fall back to the current screen size so older
    /// settings files remain usable after preset changes.
    private static func area(defaults: UserDefaults, fallbackArea: AsteriasArea) -> AsteriasArea {
        switch defaults.string(forKey: "selectedDimensions") {
        case "tinySquare":
            return AsteriasArea(width: 64, height: 64)
        case "extraSmallSquare":
            return AsteriasArea(width: 128, height: 128)
        case "smallSquare":
            return AsteriasArea(width: 256, height: 256)
        case "mediumSquare", nil:
            return AsteriasArea(width: 512, height: 512)
        case "largeSquare":
            return AsteriasArea(width: 1024, height: 1024)
        case "wallpaperHD":
            return AsteriasArea(width: 1920, height: 1080)
        case "wallpaper4K":
            return AsteriasArea(width: 3840, height: 2160)
        case "screen":
            return fallbackArea
        default:
            return fallbackArea
        }
    }

    private static func layerCount(defaults: UserDefaults) -> Int? {
        let value = defaults.integer(forKey: "selectedLayerCount")
        return value == 0 ? nil : value
    }

    static func generatorSelectionKey(for kind: GeneratorKind) -> String {
        "isGeneratorEnabled.\(kind.rawValue)"
    }

    static func isGeneratorEnabled(_ kind: GeneratorKind, defaults: UserDefaults = AsteriasSettings.defaults) -> Bool {
        defaults.object(forKey: generatorSelectionKey(for: kind)) as? Bool ?? true
    }

    /// Returns the user-enabled generator families. The renderer treats an
    /// empty set as "all" to recover from disabling every checkbox.
    static func allowedGenerators(defaults: UserDefaults = AsteriasSettings.defaults) -> Set<GeneratorKind> {
        Set(GeneratorKind.allCases.filter { isGeneratorEnabled($0, defaults: defaults) })
    }

    private static func palette(defaults: UserDefaults) -> AsteriasColorPalette {
        let presetRawValue = defaults.string(forKey: "selectedPalette") ?? AsteriasPalettePreset.random.rawValue
        let preset = AsteriasPalettePreset(rawValue: presetRawValue) ?? .random
        return preset.palette(customColors: customPaletteColors(defaults: defaults))
    }

    private static func customPaletteColors(defaults: UserDefaults) -> [AsteriasColor] {
        [
            defaults.string(forKey: "customPaletteColor1") ?? "#0B132B",
            defaults.string(forKey: "customPaletteColor2") ?? "#1C7293",
            defaults.string(forKey: "customPaletteColor3") ?? "#3DDC97",
            defaults.string(forKey: "customPaletteColor4") ?? "#F4D35E",
            defaults.string(forKey: "customPaletteColor5") ?? "#EE964B"
        ].compactMap(color(from:))
    }

    private static func color(from hex: String) -> AsteriasColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }

        return AsteriasColor(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            alpha: 0
        )
    }
}
