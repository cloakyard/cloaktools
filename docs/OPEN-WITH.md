# Open With: implemented routing and remaining Milestone 2 contract

MVP 0 receives actual HTTP, HTTPS and mailto events, discovers compatible installed destinations, excludes self, and opens a chosen app explicitly. Open Once, Copy Link, Cancel, Unknown source, failure display, and immediate loop suppression are implemented. Version 0.2.0 adds explicit persisted rules, automatic app dispatch, ordered All/Any matching, a local tester and one-time bypass. Version 0.2.1 adds separate explicit default setup and guarded restoration. Version 0.2.2 adds ordered pins and per-role fallback apps. No default changes on launch. See [routing evidence](verification/ROUTING-RULES.md) and [default-handler verification](verification/DEFAULT-HANDLERS.md).

## Two independent roles

Web (HTTP/HTTPS) and email (mailto) have separate Set Up and Restore reviews in Open With. The settings show actual discovered defaults; HTTP/HTTPS disagreement is shown explicitly. Registration in Info.plist does not establish default ownership.

Set Up reviews the current apps before the explicit Use CloakTools action. Only then is prior-handler information saved and NSWorkspace asked to set each scheme. macOS handles any consent prompt asynchronously. The app verifies actual status afterward; callback success alone is not treated as proof. Already-owned schemes are skipped without overwriting their prior app.

Restore reviews each currently owned scheme, preselecting the previous compatible app or requiring an available alternative. A default chosen elsewhere is skipped. Both role state and saved history are checked again at execution, and state is rechecked between requests. Failures/declines stop further writes. Partial changes remain visible and recoverable; no automatic rollback is attempted. NSWorkspace offers neither an atomic HTTP+HTTPS transaction nor conditional compare-and-swap, so a change made externally during an outstanding consent prompt is an unavoidable race boundary. Subsequent steps stop if that changed state is detected.

Ownership uses both bundle ID and canonical app path. A different installed copy of CloakTools is not silently changed by Restore. If no prior handler was known, or this app was selected outside its own setup flow, the user must choose an available alternative. Restore before uninstalling or deleting recovery information. Live setup/normal ingress/restart/restoration passed on macOS 27.2.1 with explicit approval, and the original Chrome/Mail defaults were restored. System failure/race cases are isolated coordinator tests; broader OS/installer lifecycle checks remain release gates.

## Chooser and rules

Production chooser: Open Once, Copy Link, Cancel, explicit persistent-rule creation, full keyboard interaction, and a visible explanation when a rule applies. Missing work destinations return to an explanatory chooser.

Precedence is (1) explicit one-time override, (2) enabled rules in visible top-to-bottom order, first match wins, (3) configured fallback, initially the chooser. The explicit one-time override bypasses both rules and fallback. A missing matching rule destination returns to the chooser and never falls through to the fallback app.

Rules support exact hostnames, explicitly opted-in subdomains, path prefixes, URL scheme, and reliable source-app identity. Each rule has Match All/Match Any, enabled state, visible priority and destination. Parse URLs; never substring-match domains (`company.example.attacker.test` must not match `company.example`). Normalize host case/IDNA deliberately, document path matching and percent encoding, and test ambiguities.

Examples: configured company domain → Edge; reliably recognized work source → Edge; configured personal destination → preferred personal browser; company mail recipient → Outlook; no match → chooser. Email recipient-domain matching uses parsed mailto addresses, not arbitrary query/body matches.

**Test a Link** shows matching rule, destination, and reason without opening or fetching anything. Rule creation is always explicit and distinct from Open Once.

## Destination management

Manage Web and Email separately in Destinations & fallback. Pin compatible apps and reorder pins through their native menus. Other compatible apps remain in alphabetical order after pins; missing pins stay visible in the manager but cannot be opened. Refresh rediscovers applications, with supported schemes shown per app.

The fallback picker starts at Show chooser. An explicitly selected app automatically receives unmatched links after Save Changes. Rules have priority; unavailable rule/fallback destinations return to the explanatory chooser without choosing another app automatically. Open a Link Once bypasses both. Test a Link reports the same rule/fallback decision without dispatch. Incoming links snapshot both rules and destination settings before queueing; compatibility is rechecked at dispatch. Management does not set OS defaults or select profiles/accounts.

## Implemented matching semantics

- Up to 64 rules, each with 1–8 conditions; a separate web/email role is always required. Empty conditions are invalid. First enabled matching rule wins; a missing destination stops evaluation and uses the chooser.
- Host conditions accept DNS-style names and IPv4, with Foundation IDNA encoding, lowercase comparison and one trailing dot removed. Exact matching excludes subdomains; the explicit subdomain condition matches the host itself or a dot-boundary suffix. Ports/userinfo/query text do not participate. IPv6 literals and wildcard syntax are not offered as host conditions.
- Path begins with is a literal, case-sensitive **URL-encoded prefix**. `/work` matches `/workshop`; use `/work/` for that folder prefix. Percent-escape hex case is normalized, but escapes are not decoded, dot segments are not resolved and query/fragment text is ignored. `/a%2Fb` differs from `/a/b`. Enter spaces as `%20` and non-ASCII text as UTF-8 percent escapes.
- Scheme is HTTP/HTTPS for Web, mailto for Email. Source is an exact bundle identifier and Unknown never matches it. The tester can simulate source. The host now accepts only a system-supplied signed-32-bit sender PID on the current Get URL event, resolving a running regular non-self app. Missing/other/brokered events remain Unknown; the live NSWorkspace probe remained Unknown. Positive source recognition is not yet live-verified.
- To-recipient-domain matches any plain ASCII dot-atom local-part address in the mailto path or `to` query field. Domains use the same IDNA normalization and exact comparison. cc/bcc/subject/body never match. Quoted local parts, display names, whitespace and ambiguous recipient lists fail closed for that condition; the original URL still goes through the chooser or other applicable conditions unchanged.
- Conditions do not fetch, resolve redirects or alter the link. Match Any is intentionally broader: any one condition can win. The rule tester identifies the matching conditions and visible rule priority.
- Bundle IDs identify destination apps, not profiles/accounts. The host rediscovers compatibility for the actual incoming URL; a saved label alone never authorizes dispatch.

The tester is File → Test a Link (⌥⌘T). File → Open a Link Once (⌥⌘O) bypasses rules and fallback explicitly and opens a chooser; the tester itself has no Open action. Chooser rule creation is explicit, with a proposed exact-host condition for a web link or mailto scheme for an email link, reviewed before saving. No query, path or body is copied into the proposed rule. A saved rule affects subsequent incoming events, not the already-open chooser. Rule snapshots are captured at URL ingress; changes while queued affect the next ingress only.

## Identity boundaries

Source application, destination application, browser profile, and signed-in account are separate models. Source detection is best effort; Unknown is normal. Never infer source from the frontmost application. An app identity proves neither mailbox, tab, nor chat workspace.

Edge application routing can use the same explicit NSWorkspace dispatch when installed. Edge was not installed on the verification Mac. Microsoft documents profile data locations and user-data policy, but that does not establish reliable macOS profile dispatch. `--profile-directory` is an investigation lead, not a shipped capability. Validate chosen sandbox/helper configuration on cold launch and already-running Edge, with multiple profiles, URLs with reserved characters, and no fallback to unintended accounts. Expose profile destinations only after both paths pass. Do not copy user profile data or install Edge during this handoff.

Email links prepare a draft; never send. Selecting a mail application does not guarantee its From account. Preserve supported recipient, cc, bcc, subject and body fields and original percent-encoding through dispatch.

## Bypasses and privacy

Ordinary browser-internal navigation, embedded web views, explicit browser launches and Universal Links may bypass the router. Browser extensions are a later enhancement. All matching remains local. Do not persist full URLs/mailto bodies by default, prefetch destinations, resolve redirects over the network, or strip query parameters. Avoid sensitive diagnostics and preserve user-controlled parameters.

## References

- [Default-handler changes and system consent](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:))
- [Apple NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [Explicit application dispatch](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:))
- [Microsoft Edge UserDataDir policy](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/userdatadir)
