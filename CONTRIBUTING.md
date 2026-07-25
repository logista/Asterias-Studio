# Forking Asterias

Asterias is published as free software for people to study, run, modify, and fork. It is not intended to be an actively maintained upstream project.

Issues and pull requests may not be reviewed. If you want to change the project, fork it and maintain your own version.

This project was written with assistance from OpenAI Codex.

## License

Forks and redistributed versions must follow the GNU General Public License, version 2 or later, as described in `LICENSE`.

## Development

1. Open `Asterias.xcodeproj` in Xcode.
2. Select the `Asterias` scheme.
3. Select the `Asterias` target, open **Signing & Capabilities**, and change **Team** to your own Apple development team or personal team.
4. If needed, change `PRODUCT_BUNDLE_IDENTIFIER` to a reverse-DNS identifier you control so Xcode can sign the app for your machine.
5. Build and run the app from Xcode.
6. Build the project and test the affected render paths before publishing your fork.

## Code Style

- Follow the existing SwiftUI structure and naming style.
- Keep generator behavior deterministic for a given seed and settings combination.
- Avoid force unwrapping unless there is a clear invariant nearby.
- Keep Metal shader changes paired with the corresponding Swift renderer changes.
- Prefer small, focused changes over broad rewrites.
