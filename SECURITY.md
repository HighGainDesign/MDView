# Security

MDView handles documents as untrusted input. Documents are read-only by default.
After explicit per-document consent, checklist interaction changes only mapped task markers
in a user-selected Markdown file. Writes validate the displayed source under
file coordination and refuse stale clicks; Quick Look and streaming cannot
write files. MDView does not execute document scripts. Raw HTML, parser plugins,
file includes, and external rendering tools are disabled. WebKit content uses a
restrictive content policy and a nonpersistent data store. Checkbox interaction
uses app-owned JavaScript in an isolated WebKit content world. Only trusted user
events from mapped checkboxes in the current main-frame render may request a
write; document HTML and scripts cannot access that bridge.

The directly distributed macOS app uses normal filesystem access rather than
App Sandbox. Local image paths, file URLs and symlinks may refer to any regular
file macOS permits the app to read; MDView imposes no document-folder boundary
or additional image-folder grants. Native reads are bounded, and image bytes
are decoded by WebKit. Hardened Runtime and Developer ID signing remain enabled.
The Quick Look extension retains its required sandbox and previews text and
embedded data images only. Remote images require a per-document HTTPS opt-in and are
always blocked in Finder Quick Look. An image request can disclose your IP
address to its host. Appearance preferences are shared only between the signed
app and its Quick Look extension through their macOS App Group.

## Reporting

Report ordinary bugs through the issue template using a sanitized example.
For a suspected vulnerability, use the repository's **Security → Report a
vulnerability** option when available. If private reporting is unavailable,
open an issue asking for a private contact without publishing exploit details,
credentials, or private documents.

Include the MDView and macOS versions, the affected surface, reproduction steps,
and a minimal sample. Security fixes target the latest release; older preview
builds are not maintained separately. There is no guaranteed response time or
bug bounty.
