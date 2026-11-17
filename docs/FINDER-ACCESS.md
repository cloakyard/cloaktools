# Finder context and access matrix

Reviewed 16 November 2026 for the local macOS 27.2.1 / arm64 build. Scope is still `~/CloakTools Files` and its descendants. Scope selection is not a filesystem permission grant.

| Context | Current entry point | Evidence / limitation |
| --- | --- | --- |
| Workspace blank space | New File, saved template, clipboard, Copy As | Actual Finder menu and file-creation paths exercised in historical integration and feature records |
| One selected workspace folder | Create inside the selected folder; Copy As | Selected-folder context inspected; native Services invocation also created inside a selected folder |
| One supported workspace image | Convert Image, Assemble PDF, Copy As | Native conversion and mixed PDF assembly exercised from actual Finder |
| Multiple workspace PDFs/images | Assemble PDF (1–32), Copy As (1–200) | Actual three-item assembly and four-item Copy As verified |
| Other selected files/folders | Finder Services and app File actions | Services are registered; native `NSPerformService` creation accepted. Permission depends on the selected location |
| Other folder blank space | No CloakTools extension menu promised | Outside the configured extension scope; use the app folder picker |
| Sidebar | Creation only if Finder supplies a usable selected folder | Callback handles this, but not every sidebar/location was runtime-tested |
| Desktop/Documents/Downloads | App action/Services, subject to macOS privacy access | No broad access grant was added; protected-folder matrix remains unverified |
| Network/removable/read-only volumes | App action/Services if accessible | Filesystem permissions and exclusive-publication support still need coverage |
| iCloud/File Provider placeholders | No universal coverage promised | Hydration, provider views, offline access and permission/restart behavior remain unverified |
| Search/Recents/Trash/other virtual views | Context-dependent | No blanket menu or destination guarantee |

Runtime records: [MVP 0](verification/MVP-0.md), [Milestone 1](verification/MILESTONE-1.md), [clipboard](verification/CLIPBOARD.md), [image conversion](verification/IMAGE-CONVERSION.md), [PDF/Copy As](verification/PDF-COPY-AS.md).

## Compact creation menu

The 0.5.0 extension offers Plain Text, Markdown and PDF directly, plus Choose File Type or Template and clipboard creation. The host catalog includes programming/JSON formats only when Developer Tools is enabled. Current preferences are read at handoff; no extension-side settings cache or new shared-storage entitlement is required. The updated menu and selected-folder handoff were verified in actual Finder.

## Configurable scopes: signing gate

The host is unsandboxed in this local preview; the Finder extension is sandboxed. Folder choices need shared durable storage so the extension can restore its scope when the host is not running. A supported App Group is the intended boundary, rather than writing directly into another process’s sandbox container or broadcasting private folder paths through unauthenticated notifications.

Apple documents two macOS group forms: `group.` identifiers require authorization in a provisioning profile; team-prefixed identifiers require the signature’s matching developer team identifier. See [Accessing app group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers) and [Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups). These are requirements for the chosen shared-container design, not a claim that every possible IPC architecture requires App Groups.

This checkout uses ad-hoc signing (`CODE_SIGN_IDENTITY = -`) with no Team ID. `security find-identity -v -p codesigning` returned **0 valid identities** during this review. No supported shared-container configuration can be verified with that signature. No copied Team ID, unprovisioned group entitlement, temporary sandbox exception or background helper was introduced. Version 0.6.0 implements configurable scope storage, host controls and extension leases, but disables them without the actual team/group entitlements. Existing workspace menus and Services remain the local-preview paths. Signing is deferred by the owner; cross-process bookmark transfer and signed lifecycle behavior are not claimed as verified.

## Implemented configuration and remaining signed checks

1. **Implemented:** `project-release.yml` supplies the same team-prefixed group to both targets. The release script takes an explicit team and valid Developer ID identity. The ad-hoc spec has no group entitlement.
2. **Implemented:** a versioned store capped at 16 folders/2 MiB, bounded read-only security-scoped bookmarks, duplicate/root validation and preservation of corrupt/future state. **Pending:** prove bookmark transfer across the actual signed host/extension boundary.
3. **Implemented:** native Add/Renew panels, removal review, and unavailable/stale feedback. A stale or moved bookmark requires reselection; it never silently broadens monitored scope.
4. **Implemented:** extension reload at launch and on a path-free change notification, actual-entitlement/container gating, balanced leases and fail-closed fallback to the workspace. Notifications are hints; stored validation remains authoritative.
5. Verify host quit, extension restart, Finder restart, scope removal, renamed/missing folders, permission revocation, multiple extension instances and installer/reinstallation behavior. Repeat the context matrix for supported protected/cloud/network locations.

The configuration code is implemented, but this record does not claim successful signed-folder runtime acceptance or a completed public-beta permission audit.
