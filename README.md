# Asterias

Asterias is a macOS SwiftUI app for creating layered procedural artwork. It builds images by combining several generator families into color layers, optionally using generated masks, then renders the result as a preview that can be exported as an image.

The app is inspired by the venerable Starfish procedural pattern generator and includes CPU renderers with Metal-backed renderers for larger outputs.

It includes three new generators: 

- Flame (inspired by ElectricSheep's Flame algorithm but doesn't actually *do* Flame algorithm)
- Julia
- Voronoi

## Project Status

This repository is published as free software for people to study, run, modify, and fork. It is not intended to be an actively maintained upstream project, and issues or pull requests may not be reviewed. If you want to change Asterias, please fork it and maintain your own version.

This project was written with assistance from OpenAI Codex.

## What It Does

Asterias Studio lets you generate abstract patterns from a configurable recipe:

- Pick an output size, from small square icons to HD, 4K, or the current screen size.
- Choose a color palette: Random, Ocean, Sunset, Forest, Neon, Pastel, Graphite, or a five-color custom palette.
- Use a random number of layers or choose a fixed layer count from 2 through 6.
- Enable tiling so compatible generators can produce repeatable texture-style output.
- Select which generator families are allowed in the render.
- Generate from a random seed or enter a seed manually for repeatable results.
- Export the current render as PNG or TIFF.

Each render is generated from a seed. Copying or reusing that seed with the same settings makes it possible to recreate a similar pattern.

## Generator Families

Asterias includes these procedural generators:

| Generator | Visual Character |
| --- | --- |
| Branchfrac | Fern-like branching distance fields |
| Bubble | Rounded cells, blobs, and overlapping lenses |
| Coswave | Radial rings and warped wave bands |
| Flame | Luminous transformed geometric filaments |
| Flatwave | Layered linear waves and interference |
| Julia | Fractal curls and escape-time contours |
| Rangefrac | Soft recursive terrain-like fields |
| Spinflake | Spiky floral forms with rotational symmetry |
| Voronoi | Cellular regions, borders, and distance ridges |

The app randomly combines enabled generators as image layers and, for some layers, as masks. This produces more varied results than a single generator on its own.


## Using The App

1. Open Asterias and choose settings in the left sidebar.
2. Click **Start Generation**.
3. Adjust the size, palette, layer count, tiling, enabled generators, or seed.
4. Click **Regenerate** to create another image.
5. Use **Copy Current Seed** to save the seed for later.
6. Choose PNG or TIFF, then click **Export Image**.

Exported images include Asterias recipe metadata. Drag an Asterias-exported PNG or TIFF back onto the canvas to restore the saved recipe settings. If the app has changed since the image was exported, regenerating from imported metadata may not be pixel-identical.

## Output Sizes

The current UI supports:

| Preset | Size |
| --- | --- |
| Tiny Square | 64 x 64 |
| Extra Small Square | 128 x 128 |
| Small Square | 256 x 256 |
| Medium Square | 512 x 512 |
| Large Square | 1024 x 1024 |
| Wallpaper HD | 1920 x 1080 |
| Wallpaper 4K | 3840 x 2160 |
| Screen | Current main screen size |

Larger renders use Metal-backed generator implementations when available.

## Development

Open `Asterias.xcodeproj` in Xcode and build or run the `Asterias` scheme with the standard Xcode controls.

### Code Signing

The checked-in project uses the original local development signing settings. I do not have a paid Apple Developer Account, so forks should expect to change the signing configuration before building or distributing the app.

In Xcode, select the `Asterias` target, open **Signing & Capabilities**, and set **Team** to your own Apple development team. If Xcode reports a bundle identifier conflict, change `PRODUCT_BUNDLE_IDENTIFIER` to a reverse-DNS identifier you control, such as `com.example.Asterias`. For local-only experimentation, you can use Xcode's personal team signing if it is available for your Apple ID.

The main implementation areas are:

- `ContentView.swift` - macOS SwiftUI interface, export, import, and settings wiring.
- `AsteriasRenderer.swift` - render options, seeded rendering, image creation, and render metrics.
- `AsteriasPattern.swift` - layered pattern composition and palettes.
- `Generators/` - procedural generator definitions.
- `Asterias*Shaders.metal` and `AsteriasMetal*Renderer.swift` - Metal shader and renderer paths.

## Forking

This project is best treated as a starting point for your own fork. Changes in forks should remain compatible with the GPL license terms.

## License

Asterias is free software licensed under the GNU General Public License, version 2 or later. See `LICENSE` for the full license text.
