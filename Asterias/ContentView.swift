import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct AsteriasApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 660)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @AppStorage("selectedDimensions", store: AsteriasSettings.defaults) private var selectedDimensions = PatternDimensions.mediumSquare
    @AppStorage("selectedPalette", store: AsteriasSettings.defaults) private var selectedPalette = AsteriasPalettePreset.random
    @AppStorage("selectedLayerCount", store: AsteriasSettings.defaults) private var selectedLayerCount = 0
    @AppStorage("isTilingEnabled", store: AsteriasSettings.defaults) private var isTilingEnabled = true
    @AppStorage("selectedExportFormat", store: AsteriasSettings.defaults) private var selectedExportFormat = ExportFormat.png
    @AppStorage("usesRandomSeed", store: AsteriasSettings.defaults) private var usesRandomSeed = true
    @AppStorage("seedText", store: AsteriasSettings.defaults) private var seedText = "1"
    @State private var enabledGenerators = AsteriasSettings.allowedGenerators()
    @State private var renderedPattern: RenderedAsteriasPattern?
    @State private var previewImage: NSImage?
    @State private var isGenerating = false
    @State private var lastRenderMetrics: AsteriasRenderMetrics?
    @State private var lastRenderContext: AsteriasRenderContext?
    @State private var isImportTargeted = false
    @State private var importMessage: String?
    @State private var errorMessage: String?

    @AppStorage("customPaletteColor1", store: AsteriasSettings.defaults) private var customPaletteColor1 = "#0B132B"
    @AppStorage("customPaletteColor2", store: AsteriasSettings.defaults) private var customPaletteColor2 = "#1C7293"
    @AppStorage("customPaletteColor3", store: AsteriasSettings.defaults) private var customPaletteColor3 = "#3DDC97"
    @AppStorage("customPaletteColor4", store: AsteriasSettings.defaults) private var customPaletteColor4 = "#F4D35E"
    @AppStorage("customPaletteColor5", store: AsteriasSettings.defaults) private var customPaletteColor5 = "#EE964B"

    private var layerCount: Int? {
        selectedLayerCount == 0 ? nil : selectedLayerCount
    }

    private var customPaletteColors: [AsteriasColor] {
        [customPaletteColor1, customPaletteColor2, customPaletteColor3, customPaletteColor4, customPaletteColor5]
            .compactMap(AsteriasColor.init(hex:))
    }

    private var selectedGeneratorSummary: String {
        let selectedCount = enabledGenerators.count
        if selectedCount == 0 {
            return "All generators fallback"
        }
        if selectedCount == GeneratorKind.allCases.count {
            return "All generators"
        }
        return "\(selectedCount) of \(GeneratorKind.allCases.count) generators"
    }

    var body: some View {
        NavigationSplitView {
            controls
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
        } detail: {
            studioPreview
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Asterias Studio")
                        .font(.title2.weight(.semibold))
                    Text("Layered procedural image generator")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                generationActions
                patternControls
                generatorControls
                seedControls
                exportControls
                #if DEBUG
                outputSummary
                performanceSummary
                #endif
                importSummary
                errorSummary
            }
            .padding(18)
        }
        .background(.thinMaterial)
    }

    private var generationActions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await regenerate() }
            } label: {
                Label(renderedPattern == nil ? "Start Generation" : "Regenerate", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)

            HStack(spacing: 10) {
                Label(selectedGeneratorSummary, systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let renderedPattern {
                    Text("Seed \(renderedPattern.seed)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var patternControls: some View {
        ControlPanel(title: "Pattern", systemImage: "square.grid.3x3") {
            Picker("Size", selection: $selectedDimensions) {
                ForEach(PatternDimensions.allCases) { dimensions in
                    Text(dimensions.label).tag(dimensions)
                }
            }

            Picker("Palette", selection: $selectedPalette) {
                ForEach(AsteriasPalettePreset.allCases) { palette in
                    Text(palette.label).tag(palette)
                }
            }

            if selectedPalette == .userDefined {
                customPaletteEditor
            }

            Picker("Layers", selection: $selectedLayerCount) {
                Text("Random").tag(0)
                ForEach(AsteriasRenderer.minimumLayerCount...AsteriasRenderer.maximumLayerCount, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }

            Toggle("Tiling", isOn: $isTilingEnabled)
        }
    }

    private var generatorControls: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    selectAllGenerators()
                } label: {
                    Label("All Generators", systemImage: "checklist.checked")
                        .frame(maxWidth: .infinity)
                }

                ForEach(GeneratorKind.sortedByName, id: \.self) { kind in
                    Toggle(isOn: generatorBinding(for: kind)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.label)
                                .font(.subheadline.weight(.medium))
                            Text(kind.helpText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Generators", systemImage: "wand.and.stars")
                .font(.headline)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var seedControls: some View {
        ControlPanel(title: "Seed", systemImage: "number") {
            Toggle("Random Seed", isOn: $usesRandomSeed)

            TextField("Seed", text: $seedText)
                .disabled(usesRandomSeed)

            Button {
                copySeed()
            } label: {
                Label("Copy Current Seed", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .disabled(renderedPattern == nil)
        }
    }

    private var exportControls: some View {
        ControlPanel(title: "Export", systemImage: "square.and.arrow.down") {
            Picker("Format", selection: $selectedExportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }

            Button {
                exportImage()
            } label: {
                Label("Export Image", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .disabled(renderedPattern == nil || isGenerating)
        }
    }

    private var outputSummary: some View {
        Group {
            if let renderedPattern {
                ControlPanel(title: "Output", systemImage: "info.circle") {
                    LabeledContent("Pixels", value: "\(renderedPattern.width) x \(renderedPattern.height)")
                    LabeledContent("Format", value: selectedExportFormat.label)
                    LabeledContent("Palette", value: lastRenderContext?.paletteLabel ?? selectedPalette.label)
                    LabeledContent("Tiling", value: (lastRenderContext?.isTilingEnabled ?? isTilingEnabled) ? "On" : "Off")
                    LabeledContent("Generators", value: lastRenderContext?.generatorSummary ?? selectedGeneratorSummary)
                }
            }
        }
    }

    private var performanceSummary: some View {
        Group {
            if let lastRenderMetrics {
                ControlPanel(title: "Performance", systemImage: "speedometer") {
                    LabeledContent("Render Total", value: AsteriasRenderMetrics.format(lastRenderMetrics.totalSeconds))
                    LabeledContent("Pattern", value: AsteriasRenderMetrics.format(lastRenderMetrics.patternSeconds))
                    LabeledContent("RGBA", value: AsteriasRenderMetrics.format(lastRenderMetrics.rgbaSeconds))
                    LabeledContent("Image", value: AsteriasRenderMetrics.format(lastRenderMetrics.imageSeconds))
                    if let slowestGeneratorMetric = lastRenderMetrics.slowestGeneratorMetric {
                        LabeledContent("Slowest", value: slowestGeneratorMetric.formattedSummary)
                    }
                }
            }
        }
    }

    private var importSummary: some View {
        Group {
            if let importMessage {
                Text(importMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var errorSummary: some View {
        Group {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var customPaletteEditor: some View {
        VStack(spacing: 8) {
            ColorPicker("Color 1", selection: customColorBinding($customPaletteColor1), supportsOpacity: false)
            ColorPicker("Color 2", selection: customColorBinding($customPaletteColor2), supportsOpacity: false)
            ColorPicker("Color 3", selection: customColorBinding($customPaletteColor3), supportsOpacity: false)
            ColorPicker("Color 4", selection: customColorBinding($customPaletteColor4), supportsOpacity: false)
            ColorPicker("Color 5", selection: customColorBinding($customPaletteColor5), supportsOpacity: false)
        }
    }

    private var studioPreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Canvas")
                        .font(.title3.weight(.semibold))
                    Text(renderedPattern.map { "\($0.width) x \($0.height)" } ?? "Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await regenerate() }
                } label: {
                    Label("Regenerate", systemImage: "sparkles")
                }
                .disabled(isGenerating)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.regularMaterial)

            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(32)
                        .shadow(color: .black.opacity(0.2), radius: 24, y: 14)
                } else {
                    ContentUnavailableView("Ready", systemImage: "sparkles", description: Text("Choose generator families and start generation."))
                }

                if isGenerating {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Generating")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                if isImportTargeted {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 34, weight: .semibold))
                        Text("Drop Asterias Image")
                            .font(.headline)
                        Text("Recipe settings will be restored if metadata is present.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.tint, lineWidth: 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $isImportTargeted, perform: importDroppedItems)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @MainActor
    private func regenerate() async {
        isGenerating = true
        errorMessage = nil

        do {
            let context = currentRenderContext(seed: try selectedSeed())
            let options = renderOptions(context: context)
            let pattern = try await Task.detached(priority: .userInitiated) {
                try AsteriasRenderer.render(options: options)
            }.value

            renderedPattern = pattern
            lastRenderMetrics = pattern.metrics
            lastRenderContext = context.resolved(seed: pattern.seed)
            seedText = "\(pattern.seed)"
            previewImage = NSImage(cgImage: pattern.cgImage, size: NSSize(width: pattern.width, height: pattern.height))
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    @MainActor
    private func exportImage() {
        guard let renderedPattern else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [selectedExportFormat.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFilename(for: renderedPattern)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let recipe = try exportRecipe(for: renderedPattern)
            try writeImage(renderedPattern.cgImage, to: url, format: selectedExportFormat, metadata: recipe)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renderOptions(context: AsteriasRenderContext) -> AsteriasRenderOptions {
        AsteriasRenderOptions(
            area: selectedDimensions.area,
            layerCount: layerCount,
            palette: selectedPalette.palette(customColors: customPaletteColors),
            isTilingEnabled: isTilingEnabled,
            allowedGenerators: enabledGenerators,
            seed: context.seed
        )
    }

    private func selectedSeed() throws -> UInt64? {
        guard !usesRandomSeed else { return nil }
        return try parseSeed(seedText)
    }

    private func parseSeed(_ text: String) throws -> UInt64 {
        guard let seed = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AsteriasError.invalidSeed
        }
        return seed
    }

    private func copySeed() {
        guard let renderedPattern else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(renderedPattern.seed)", forType: .string)
    }

    private func customColorBinding(_ storage: Binding<String>) -> Binding<Color> {
        Binding {
            Color(hex: storage.wrappedValue) ?? .white
        } set: { newValue in
            storage.wrappedValue = newValue.hexRGB ?? storage.wrappedValue
        }
    }

    private func generatorBinding(for kind: GeneratorKind) -> Binding<Bool> {
        Binding {
            enabledGenerators.contains(kind)
        } set: { isEnabled in
            if isEnabled {
                enabledGenerators.insert(kind)
            } else {
                enabledGenerators.remove(kind)
            }
            AsteriasSettings.defaults.set(isEnabled, forKey: AsteriasSettings.generatorSelectionKey(for: kind))
        }
    }

    private func currentRenderContext(seed: UInt64?) -> AsteriasRenderContext {
        let allowed = enabledGenerators.isEmpty ? Set(GeneratorKind.allCases) : enabledGenerators
        return AsteriasRenderContext(
            seed: seed,
            dimensionsLabel: selectedDimensions.label,
            requestedLayerCount: layerCount,
            paletteLabel: selectedPalette.label,
            customPaletteHexColors: selectedPalette == .userDefined ? [customPaletteColor1, customPaletteColor2, customPaletteColor3, customPaletteColor4, customPaletteColor5] : [],
            isTilingEnabled: isTilingEnabled,
            allowedGenerators: GeneratorKind.sortedByName.filter { allowed.contains($0) }
        )
    }

    private func selectAllGenerators() {
        enabledGenerators = Set(GeneratorKind.allCases)
        for kind in GeneratorKind.allCases {
            AsteriasSettings.defaults.set(true, forKey: AsteriasSettings.generatorSelectionKey(for: kind))
        }
    }

    private func defaultExportFilename(for renderedPattern: RenderedAsteriasPattern) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Asterias-\(renderedPattern.width)x\(renderedPattern.height)-\(formatter.string(from: Date())).\(selectedExportFormat.fileExtension)"
    }

    private func exportRecipe(for renderedPattern: RenderedAsteriasPattern) throws -> String {
        let context = lastRenderContext ?? currentRenderContext(seed: renderedPattern.seed).resolved(seed: renderedPattern.seed)
        let formatter = ISO8601DateFormatter()
        let recipe = AsteriasExportRecipe(
            app: "Asterias",
            recipeVersion: AsteriasExportRecipe.currentVersion,
            appBuild: Bundle.main.appBuildDescription,
            exportedAt: formatter.string(from: Date()),
            seed: renderedPattern.seed,
            width: renderedPattern.width,
            height: renderedPattern.height,
            requestedLayerCount: context.requestedLayerCount,
            renderedLayerCount: renderedPattern.metrics.layerCount,
            palette: context.paletteLabel,
            customPaletteHexColors: context.customPaletteHexColors,
            isTilingEnabled: context.isTilingEnabled,
            allowedGenerators: context.allowedGenerators.map(\.rawValue),
            generatorSequence: renderedPattern.metrics.generatorMetrics.map(AsteriasGeneratorUse.init(metric:))
        )
        let data = try JSONEncoder.sortedPrettyPrinted.encode(recipe)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ExportError.metadataEncodingFailed
        }
        return string
    }

    private func writeImage(_ image: CGImage, to url: URL, format: ExportFormat, metadata: String) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.contentType.identifier as CFString, 1, nil) else {
            throw ExportError.encodingFailed(format.label)
        }

        let properties = format.imageProperties(metadata: metadata)
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.encodingFailed(format.label)
        }
    }

    private func importDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = droppedFileURL(from: item) else { return }
                importRecipe(from: url)
            }
            return true
        }
        return false
    }

    private func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        return nil
    }

    private func importRecipe(from url: URL) {
        do {
            let recipe = try AsteriasExportRecipe.read(from: url)
            Task { @MainActor in
                applyImportedRecipe(recipe)
            }
        } catch {
            Task { @MainActor in
                importMessage = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func applyImportedRecipe(_ recipe: AsteriasExportRecipe) {
        usesRandomSeed = false
        seedText = "\(recipe.seed)"
        selectedDimensions = PatternDimensions.matching(width: recipe.width, height: recipe.height) ?? .mediumSquare
        selectedLayerCount = recipe.requestedLayerCount ?? 0
        selectedPalette = AsteriasPalettePreset(label: recipe.palette) ?? .random
        isTilingEnabled = recipe.isTilingEnabled

        if selectedPalette == .userDefined {
            let colors = recipe.customPaletteHexColors
            customPaletteColor1 = colors[safe: 0] ?? customPaletteColor1
            customPaletteColor2 = colors[safe: 1] ?? customPaletteColor2
            customPaletteColor3 = colors[safe: 2] ?? customPaletteColor3
            customPaletteColor4 = colors[safe: 3] ?? customPaletteColor4
            customPaletteColor5 = colors[safe: 4] ?? customPaletteColor5
        }

        let importedGenerators = Set(recipe.allowedGenerators.compactMap(GeneratorKind.init(rawValue:)))
        enabledGenerators = importedGenerators.isEmpty ? Set(GeneratorKind.allCases) : importedGenerators
        for kind in GeneratorKind.allCases {
            AsteriasSettings.defaults.set(enabledGenerators.contains(kind), forKey: AsteriasSettings.generatorSelectionKey(for: kind))
        }

        let allowed = enabledGenerators.isEmpty ? Set(GeneratorKind.allCases) : enabledGenerators
        lastRenderContext = AsteriasRenderContext(
            seed: recipe.seed,
            dimensionsLabel: selectedDimensions.label,
            requestedLayerCount: layerCount,
            paletteLabel: selectedPalette.label,
            customPaletteHexColors: selectedPalette == .userDefined ? [customPaletteColor1, customPaletteColor2, customPaletteColor3, customPaletteColor4, customPaletteColor5] : [],
            isTilingEnabled: isTilingEnabled,
            allowedGenerators: GeneratorKind.sortedByName.filter { allowed.contains($0) }
        )
        importMessage = "Imported Asterias recipe. Things may have changed since it was exported, so regenerating may not be exact."
        errorMessage = nil
    }
}

private struct ControlPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AsteriasRenderContext: Sendable {
    let seed: UInt64?
    let dimensionsLabel: String
    let requestedLayerCount: Int?
    let paletteLabel: String
    let customPaletteHexColors: [String]
    let isTilingEnabled: Bool
    let allowedGenerators: [GeneratorKind]

    var generatorSummary: String {
        if allowedGenerators.count == GeneratorKind.allCases.count {
            return "All generators"
        }
        return allowedGenerators.map(\.label).joined(separator: ", ")
    }

    func resolved(seed: UInt64) -> AsteriasRenderContext {
        AsteriasRenderContext(
            seed: seed,
            dimensionsLabel: dimensionsLabel,
            requestedLayerCount: requestedLayerCount,
            paletteLabel: paletteLabel,
            customPaletteHexColors: customPaletteHexColors,
            isTilingEnabled: isTilingEnabled,
            allowedGenerators: allowedGenerators
        )
    }
}

private struct AsteriasExportRecipe: Codable {
    static let currentVersion = 1

    let app: String
    let recipeVersion: Int?
    let appBuild: String?
    let exportedAt: String
    let seed: UInt64
    let width: Int
    let height: Int
    let requestedLayerCount: Int?
    let renderedLayerCount: Int
    let palette: String
    let customPaletteHexColors: [String]
    let isTilingEnabled: Bool
    let allowedGenerators: [String]
    let generatorSequence: [AsteriasGeneratorUse]

    static func read(from url: URL) throws -> AsteriasExportRecipe {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let metadata = metadataString(from: properties) else {
            throw ImportError.missingRecipe
        }

        let data = Data(metadata.utf8)
        let recipe = try JSONDecoder().decode(AsteriasExportRecipe.self, from: data)
        guard recipe.app == "Asterias" else {
            throw ImportError.missingRecipe
        }
        return recipe
    }

    private static func metadataString(from properties: [CFString: Any]) -> String? {
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
           let description = png[kCGImagePropertyPNGDescription] as? String {
            return description
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let description = tiff[kCGImagePropertyTIFFImageDescription] as? String {
            return description
        }
        return nil
    }
}

private struct AsteriasGeneratorUse: Codable {
    let layer: Int
    let role: String
    let generator: String

    init(metric: AsteriasGeneratorMetric) {
        layer = metric.layerIndex + 1
        role = metric.role.label
        generator = metric.kind.rawValue
    }
}

private enum PatternDimensions: String, CaseIterable, Identifiable {
    case tinySquare
    case extraSmallSquare
    case smallSquare
    case mediumSquare
    case largeSquare
    case wallpaperHD
    case wallpaper4K
    case screen

    var id: String { rawValue }

    var label: String {
        let area = area
        switch self {
        case .screen:
            return "Screen (\(area.width) x \(area.height))"
        default:
            return "\(area.width) x \(area.height)"
        }
    }

    var area: AsteriasArea {
        switch self {
        case .tinySquare:
            AsteriasArea(width: 64, height: 64)
        case .extraSmallSquare:
            AsteriasArea(width: 128, height: 128)
        case .smallSquare:
            AsteriasArea(width: 256, height: 256)
        case .mediumSquare:
            AsteriasArea(width: 512, height: 512)
        case .largeSquare:
            AsteriasArea(width: 1024, height: 1024)
        case .wallpaperHD:
            AsteriasArea(width: 1920, height: 1080)
        case .wallpaper4K:
            AsteriasArea(width: 3840, height: 2160)
        case .screen:
            PatternDimensions.mainScreenArea
        }
    }

    private static var mainScreenArea: AsteriasArea {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return AsteriasArea(width: max(1, Int(frame.width)), height: max(1, Int(frame.height)))
    }
}

private enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case tiff

    var id: String { rawValue }

    var label: String {
        switch self {
        case .png: "PNG"
        case .tiff: "TIFF"
        }
    }

    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .tiff: .tiff
        }
    }

    func imageProperties(metadata: String) -> [CFString: Any] {
        switch self {
        case .png:
            return [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyPNGDescription: metadata
                ]
            ]
        case .tiff:
            return [
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFImageDescription: metadata,
                    kCGImagePropertyTIFFSoftware: "Asterias"
                ]
            ]
        }
    }
}

private enum ExportError: LocalizedError {
    case encodingFailed(String)
    case metadataEncodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let format):
            return "Could not encode the current pattern as \(format)."
        case .metadataEncodingFailed:
            return "Could not encode the generation metadata."
        }
    }
}

private enum ImportError: LocalizedError {
    case missingRecipe

    var errorDescription: String? {
        switch self {
        case .missingRecipe:
            return "That image does not contain Asterias recipe metadata."
        }
    }
}

private extension AsteriasPalettePreset {
    init?(label: String) {
        guard let preset = Self.allCases.first(where: { $0.label == label }) else { return nil }
        self = preset
    }
}

private extension PatternDimensions {
    static func matching(width: Int, height: Int) -> PatternDimensions? {
        allCases.first { dimensions in
            let area = dimensions.area
            return area.width == width && area.height == height
        }
    }
}

private extension AsteriasColor {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }

        red = Double((value >> 16) & 0xFF) / 255.0
        green = Double((value >> 8) & 0xFF) / 255.0
        blue = Double(value & 0xFF) / 255.0
        alpha = 0
    }
}

private extension Color {
    init?(hex: String) {
        guard let asteriasColor = AsteriasColor(hex: hex) else { return nil }
        self.init(red: asteriasColor.red, green: asteriasColor.green, blue: asteriasColor.blue)
    }

    var hexRGB: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let red = Int((color.redComponent * 255.0).rounded()).clamped(to: 0...255)
        let green = Int((color.greenComponent * 255.0).rounded()).clamped(to: 0...255)
        let blue = Int((color.blueComponent * 255.0).rounded()).clamped(to: 0...255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension JSONEncoder {
    static var sortedPrettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension Bundle {
    var appBuildDescription: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [version, build].compactMap { $0 }.joined(separator: " (") + (version != nil && build != nil ? ")" : "")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    ContentView()
}
