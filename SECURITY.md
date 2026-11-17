# Security

CloakTools handles local files and potentially sensitive URLs. This local build is an ad-hoc signed development preview, not a hardened/notarized distribution.

The host is outside App Sandbox; macOS permissions still apply. The Finder extension is sandboxed and holds no settings copy or file-operation engine. External action URLs are untrusted: validate their shape and show a confirmation before writing. Generated source is inert text and is never executed. Image input is content-validated and bounded; native decoders are not a substitute for validation. Output publication must never overwrite existing files or follow an existing destination symlink.

Routing must explicitly target a non-self app, preserve URLs, avoid network prefetch/history, and not infer accounts from app identity. Do not add shell interpolation of incoming URLs or template names. Never log real full URLs, tokens, recipients or message bodies. The routing probe is synthetic-test-only and is not shipped.

For a suspected vulnerability, prepare minimal reproduction steps with synthetic data and share them privately with the maintainer through an established private contact. No public security contact or advisory channel is configured in this local handoff. Do not post credentials or private documents to a public issue. A public disclosure route must be established before beta.
