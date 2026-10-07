# Security

MDView handles documents as untrusted input. It is a read-only viewer: it does
not save Markdown files or execute document scripts. Raw HTML, parser plugins,
file includes, and external rendering tools are disabled. WebKit content uses a
restrictive content policy and a nonpersistent data store.

Local image access is restricted to the document's folder or an explicitly
granted image folder. Remote images require a per-document HTTPS opt-in and are
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
