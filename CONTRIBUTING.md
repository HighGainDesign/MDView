# Contributing to MDView

MDView is a small, read-only Markdown viewer. Changes should make reading faster
or clearer while keeping the app simple. Version 1.0 focuses on macOS; a possible
2.0 may bring the same reader to iOS.

## Issues and proposals

For a bug, include your macOS version, MDView version, expected behavior, actual
behavior, and a small Markdown example. Explain whether the problem occurs in
the app, Finder Quick Look, or the Drafts action. Replace private content with a
minimal example before sharing it.

Discuss substantial features before opening a large pull request. Specialized
Markdown extensions, editing, and export workflows are outside the initial
release scope.

## Local development

Use Xcode 26 or later, its command-line tools, and XcodeGen 2.44 or later. The app
supports macOS 14 and later. See the README for build and test commands.

`project.yml` is the authoritative project definition; the generated
`MDView.xcodeproj` is ignored. Dependency versions are pinned there. Tests run
with isolated preferences so an ad-hoc test host does not request access to the
signed app's shared settings container.

For signed builds with your own Apple team, replace `DEVELOPMENT_TEAM` in
`project.yml` and the team prefix in both application-group entitlement entries
and `Shared/ReaderPreferences.swift`. Keep the app and Quick Look extension in
the same group and sign both with the same team. App Group access is verified
separately in a signed Finder preview. Never grant broad access to other apps'
data to make an ad-hoc build work.

The main code boundaries are:

- `App/`: document lifecycle, SwiftUI reader, settings, and file refresh.
- `QuickLook/`: Finder's data-based preview provider.
- `Shared/`: parser, HTML adaptation, styles, and shared preferences. Keep this
  layer free of AppKit so it can serve a future iOS reader.
- `Tests/`: renderer, change review, preferences, WebKit, and window checks.
- `Integrations/Drafts/`: action resource and URL integration.
- `script/`: local build and release packaging.

## Pull requests

Keep each pull request focused. Explain the user-visible problem, the resulting
behavior, and how you checked it. Add a regression test when a change affects
parsing, permissions, preferences, or document lifecycle. For layout changes,
include a screenshot made with a non-private sample document.

Run the relevant tests and check Finder Quick Look when shared rendering or
extension behavior changes. Verify light/dark appearance, tables, links, and
automatic refresh when they are affected. A change must preserve read-only file
handling, bounded image access, and inert HTML/scripts.

Do not commit signing certificates, private keys, provisioning profiles, build
products, personal settings, or local agent notes. After testing, close and
remove temporary app bundles and eject old installers; macOS can discover those
copies in Open With and Extensions.

## Releases

Maintainers use `script/release.sh` to build universal binaries, sign the app and
extension, notarize both the app and DMG, and staple their tickets. The GitHub
release workflow runs on a matching `vX.Y.Z` tag from the default branch. Its
release environment is restricted to approved version tags; Apple credentials
are encrypted environment secrets. Every tagged release runs tests before
loading credentials, validates signatures and notarization, and publishes the
DMG with its checksum. Versions below 1.0 are marked as previews. Contributions
do not need access to release credentials.

By submitting a contribution, you agree to license it under the repository's
MIT license. Retain third-party license notices when changing dependencies.
