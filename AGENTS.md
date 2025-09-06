# Repository Guidelines

This is a Flutter/Dart mono‑repo containing multiple packages that work together to power Super Editor and related tooling.

## Project Structure & Module Organization
- `super_editor/`: Core editor widgets and example app.
- `super_text_layout/`, `attributed_text/`: Text layout primitives and models.
- `super_editor_markdown/`, `super_editor_quill/`: Format parsers/serializers.
- `super_keyboard/`, `super_editor_clipboard/`, `super_editor_spellcheck/`: Platform and UX integrations.
- `super_clones/`: Example apps (e.g., Google Docs, Slack) demonstrating patterns.
- `golden_runner/`: Utility to run/update golden tests in a stable environment.
- `doc/website/`, `website/`: Documentation site sources and assets.

## Build, Test, and Development Commands
Run commands from an individual package directory unless noted.
- Install deps: `flutter pub get`
- Analyze code: `dart analyze .`
- Format code (check): `dart format -o none --set-exit-if-changed .`
- Run unit tests: `flutter test`
- Update goldens: `flutter test --update-goldens`
- Golden runner (from a package): `flutter pub run ../golden_runner/tool/goldens test` (or `update`)

## Coding Style & Naming Conventions
- Style: Inherits `flutter_lints` via `analysis_options.yaml`.
- Indentation: 2 spaces; no hard tabs.
- Files: `lower_snake_case.dart`; Types: `UpperCamelCase`; members/functions: `lowerCamelCase`.
- Keep public API docs concise; prefer clear naming over comments.

## Testing Guidelines
- Framework: `flutter_test`; goldens live under `test_goldens/`.
- Unit tests: place in `test/` with `*_test.dart` names.
- Run impacted package tests before pushing; update goldens only when visuals intentionally change.
- For goldens, prefer `golden_runner` for consistent rendering across platforms.

## Commit & Pull Request Guidelines
- Messages: Use scoped summaries, e.g. `[SuperEditor][Bug] - Fix caret crash (Resolves #1234)`.
- Link issues with `Resolves #NNN`; reference PR in description if needed.
- PRs: include clear description, reproduction steps, and screenshots/GIFs for UI changes; update docs when behavior or APIs change.
- Keep changes atomic per package; include tests for new behavior.

## Notes for Contributors
- Branches: target `main`; coordinate with maintainers for `stable` backports.
- Mono‑repo versioning: when updating one package, ensure dependent packages in this repo still build/tests pass.
