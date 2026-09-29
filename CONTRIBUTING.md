# Contributing to Aurolight

Setup is in [Getting started](README.md#getting-started), the folder layout and make commands in
[Development](README.md#development). To support a new controller, see
[Adding a board](firmware/README.md#adding-a-board).

Open `macos/Package.swift` in Xcode (it includes `core/`); `make test` runs both test suites. Launch the app with
`make run`: Screen Recording needs the signed app bundle.

## Where code goes

- **AurolightCore (`core/`):** everything that can be a pure function or value: sampling, detection, color,
  effects, protocol encoding and pacing. No UI, devices, clocks or Apple frameworks; time comes in as a parameter.
  CI builds and tests it on Linux. New logic comes with tests.
- **Aurolight (`macos/`):** screen capture, audio, serial ports, timers, permissions, settings and the UI.
  `LightEngine` reaches the controller only through `LightOutput` and the screen only through `CaptureSource`, so
  its tests use fakes for both. A new kind of output (e.g. network) is a new `LightOutput` and
  `OutputConfiguration` case; the engine doesn't change.
- **Firmware:** receives frames and drives the strip. Effects are rendered in the app, not here.

## Guidelines

- English only, American spelling.
- User-facing text says "controller" and "LED strip"; board names belong in `firmware/` and the setup docs.
- Saved settings must keep loading: decode new fields with `decode(_:default:)`.
- Install `clang-format shellcheck swiftlint periphery` with Homebrew and run `make hooks` once.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, …): they
  set the next version and the changelog.
- For detection or sampling changes, compare `make benchmark` and `make benchmark-footage` before and after.

## Adding an effect

1. Add a case to `LightMode` and to its `controls` switch (`core/Sources/AurolightCore/Effects/EffectSettings.swift`).
2. Write the effect in its own file, `core/Sources/AurolightCore/Effects/Library/<Name>Effect.swift`, with
   `static func colors(in context: EffectContext) -> [RGB]`: a pure function of time, settings and LED position.
   Take its pace from `context.rate(slowest:fastest:)`, in real units (laps, pulses or cycles per second).
3. Add one line to the switch in `EffectRenderer.swift`, and one to `presentation` in
   `macos/Sources/Aurolight/Views/Components/LightMode+UI.swift` (title, SF Symbol, menu group).
4. Add `core/Tests/AurolightCoreTests/Effects/<Name>EffectTests.swift`.
