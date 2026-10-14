# Changelog

## 1.2.2 — 2026-10-14

First published 1.2 release. The unpublished 1.2.0 and 1.2.1 tags stopped at hosted
tests. Layout tests now retain their requested window sizes on small virtual
displays, and WebKit tests compare document identity directly instead of using
rounded clock values.

- Local images use normal macOS filesystem access, including relative paths, absolute paths, local file URLs and symlinks. Image-folder grants and document-folder boundaries have been removed; macOS privacy and file permissions still apply. Remote images remain off by default.
- Click a task checkbox to allow automatic checkmark saves for that document. Cancel makes no change; confirming also saves the first tick. Only the marker changes; Undo/Redo is available.
- “Stop Saving Checkmarks” keeps saved progress and asks again before future checkbox changes; the action replaces the ambiguous “Read Only” label.
- Checking a task keeps the document at its current scroll position, without briefly jumping to the top.
- Change review uses a docked sidebar, moving below the document in narrow windows, so review controls no longer cover the changed text.
- Undo and Redo act on an active text field before checklist history, so editing a Find query does not change saved checkmarks.
- Find returns keyboard focus to its search field when requested again after navigating the document, including when its bar is already open.
- Task checkboxes expose their text as accessible names, have larger targets and keep keyboard focus after a save or canceled consent. Outline levels, settings help and reduced-motion scrolling are improved.
- A Markdown link immediately following a table no longer appears a second time as a generated table caption.
- Stale checkbox clicks are refused and refreshed when another writer changed the file. Encodings, line endings and permissions are preserved. Quick Look, snapshots and live streams remain read-only.

## 1.1.0 — 2026-10-07

- Review saved changes individually with Previous/Next, Mark This Reviewed, and Mark All Reviewed. Acknowledgement advances the in-memory baseline without editing the file; later edits to reviewed text reappear for review.
- Separate reader actions from passive update status and word count, with visible button controls and clearer Pause/Resume and Review Changes actions.
- Live Streaming Preview reads the public Marked-compatible stream while Marked stays
  closed. Drafts is tested; other publishers are accepted, with optional source
  app names shown in the footer. Open it from File, Settings, the welcome window, or `mdview://stream`.
- Pause keeps the current preview; Resume catches up. Closing the window stops
  reading. The ordinary clipboard and source drafts are never changed.
- The existing Drafts action still sends snapshots, and saved-file change review
  remains separate from the live draft stream.

## 1.0.0

First stable macOS release, with the reader behavior tested in the previews:

- Native read-only Markdown windows, automatic refresh, and saved-change review.
- Tables, links, lists, code blocks, and footnotes using Apex.
- Outline navigation, find, zoom, and per-window reading width.
- System, Light, and Dark appearance shared with Finder Quick Look.
- Optional Drafts action installed from Settings or the setup guide.
- Automatic local images with scoped folder grants, and per-document HTTPS
  image opt-in.
- Universal Apple Silicon and Intel DMG, Developer ID signed and notarized by
  Apple through the tag-driven GitHub workflow.

The stable release is marked Latest on GitHub, with a prominent README download
link. Markdown rendering and reader behavior are unchanged from 0.2.6.

## 0.2.6 — Preview

- Configure tag-driven GitHub builds with Developer ID signing, Apple
  notarization, stapled tickets, and published DMG checksums.
- Restrict release credentials to approved version tags and mark 0.x releases
  as previews automatically.

The reader and Quick Look behavior are unchanged from 0.2.5.

## 0.2.5 — Preview

Initial public-release candidate for the macOS reader:

- Native read-only document windows with automatic refresh and change review.
- Apex Markdown rendering for tables, links, lists, code, and footnotes.
- Outline navigation, find, zoom, and per-window reading width.
- System, Light, and Dark appearance shared with Finder Quick Look.
- Optional Drafts action installed from Settings or the setup guide.
- Automatic local images with scoped folder grants, and per-document HTTPS
  image opt-in.
- Universal Apple Silicon and Intel app with a drag-to-Applications DMG.

This is a preview version. Version 1.0 targets macOS; an iOS reader is a possible
part of version 2.0.
