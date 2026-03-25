# Remote Rich Clipboard Forwarding (Draft Spec)

## Summary
Add host-to-remote clipboard forwarding for non-text payloads, starting with images, so a user can press paste in VVTerm and have the image become usable on the remote machine.

Draft date: 2026-03-25

Core V1 behavior:
- Text clipboard keeps using normal terminal paste.
- Image clipboard is uploaded to the remote host as a temporary file.
- VVTerm uses a layered fallback strategy:
  - future terminal-native rich clipboard path via Kitty `OSC 5522` when supported
  - remote machine clipboard seeding from the temporary file
  - temporary remote file path insertion into the active terminal session

This is aimed at modern agent workflows where the remote CLI may prefer native clipboard paste behavior, but can still fall back to consuming a remote file path.

## Problem
Today VVTerm forwards clipboard reads through Ghostty as text only.

That is correct for normal terminal paste, but it breaks down for rich clipboard content:
- `Cmd+V` / `Ctrl+V` works for plain text.
- If the host clipboard contains an image, there is no terminal-native representation that an SSH shell can safely consume.
- Users increasingly want to paste screenshots and other images into remote coding/agent workflows.

The current pipeline is explicitly text-only:
- [Clipboard.swift](/Users/uyakauleu/vivy/development/VivyTerm/VVTerm/Utilities/Clipboard.swift)
- [Ghostty.App.swift](/Users/uyakauleu/vivy/development/VivyTerm/VVTerm/GhosttyTerminal/Ghostty.App.swift)

## Why Normal Paste Cannot Solve This
Terminal paste is fundamentally a byte stream into stdin, not a file transfer channel.

Relevant constraints:
- Ghostty clipboard read currently returns a C string to `ghostty_surface_complete_clipboard_request`.
- Bracketed paste is text-oriented and protects command boundaries, not binary payloads.
- OSC 52 is also clipboard text transport, not arbitrary file delivery.
- Sending raw image bytes into the shell would corrupt terminal input and would still not create a usable remote file.
- Kitty `OSC 5522` is the right terminal-native model for rich clipboard transfer, but Ghostty currently parses and does not yet implement it end-to-end.
- Mosh should be assumed incompatible with Kitty rich clipboard semantics and even has mixed support for OSC 52-style clipboard workflows.

Conclusion:
- Rich clipboard forwarding still needs a separate remote transfer path.
- Terminal-native rich clipboard support should be treated as an optimization layer above that transfer path, not a replacement for it.
- The terminal input stream should only receive normal paste input after the clipboard path is prepared, or a textual fallback reference to the transferred asset.

## Goals (V1)
- Support pasting host clipboard images into a remote SSH session in a way that is useful immediately.
- Preserve current text paste behavior.
- Work on both macOS and iOS.
- Keep the user flow close to normal paste.
- Avoid shell corruption and avoid depending on terminal escape hacks.
- Keep Mosh sessions supported by using SSH as the transfer side channel.
- Prefer remote-native clipboard behavior when the remote host supports it.
- Support a future terminal-native rich clipboard path where terminal and remote TUI both speak Kitty `OSC 5522`.

## Non-Goals (V1)
- Arbitrary clipboard format sync between host and remote.
- Direct binary injection into terminal stdin.
- Full remote file browser integration.
- Bidirectional rich clipboard sync from remote back to host.
- Semantic per-agent integrations beyond pasting a remote file path.
- Copying terminal-rendered images out of the remote session.

## User Stories
- As a user, when my clipboard contains text, paste behaves exactly like today.
- As a user, when my clipboard contains a screenshot, paste makes that image available in the remote machine clipboard when possible.
- As a user, after image paste completes, I can immediately reference the uploaded file in Codex or another agent running on the server.
- As a user on Mosh, image paste still works even though terminal traffic is not going through the SSH shell channel.

## Proposed UX

### Default behavior
When the terminal is focused and the user triggers paste:

1. VVTerm inspects the host clipboard.
2. If clipboard has text and no richer supported payload, use existing `paste_from_clipboard`.
3. If clipboard has an image, VVTerm uploads the image to a temporary file on the remote host.
4. VVTerm checks whether terminal-native rich clipboard transfer is available for this session.
5. If Kitty `OSC 5522` is supported and succeeds, VVTerm uses normal native paste semantics.
6. Otherwise VVTerm tries to copy that image into the remote machine clipboard.
7. If remote clipboard seeding succeeds, VVTerm triggers normal paste behavior.
8. If remote clipboard seeding fails or is unsupported, VVTerm pastes the temporary remote absolute path as text into the terminal.

Example pasted text:
```text
/tmp/vvterm-clipboard-a1b2c3.png
```

### User feedback
- While uploading: lightweight non-terminal progress UI.
- On success: optional toast, no modal interruption.
- On failure: show actionable error and do not inject partial text.
- If VVTerm had to fall back from Kitty `5522` to remote clipboard seeding or from remote clipboard seeding to file path insertion, the UI should say so clearly.

### Settings
Add terminal settings:
- `Rich Clipboard Paste`: `Off | Ask | Auto`
- `Terminal Rich Clipboard`: `Auto | Prefer Kitty | Disable Kitty`
- `Remote Clipboard Strategy`: `Prefer Native Clipboard | File Path Only`
- `Image Paste Format`: `PNG | JPEG`
- `Paste Insert Style`: `Path only | Quoted path`

Recommended default:
- `Rich Clipboard Paste = Ask` for the first release.

### Ask mode behavior
If an image is on the clipboard, prompt:
- `Upload image to remote host and prepare remote paste?`

Actions:
- `Upload and Paste`
- `Paste Text Instead` if clipboard also contains text
- `Cancel`

## Proposed Technical Design

### 1) Split text paste from rich paste
Keep the existing Ghostty clipboard callback for text.

Add a higher-level paste router in the terminal view layer:
- inspect pasteboard contents before calling Ghostty `paste_from_clipboard`
- route to:
  - `plainTextPaste`
  - `remoteRichPaste`

Likely touchpoints:
- [GhosttyTerminalView+iOS.swift](/Users/uyakauleu/vivy/development/VivyTerm/VVTerm/GhosttyTerminal/GhosttyTerminalView+iOS.swift)
- [GhosttyTerminalView+macOS.swift](/Users/uyakauleu/vivy/development/VivyTerm/VVTerm/GhosttyTerminal/GhosttyTerminalView+macOS.swift)
- [SSHTerminalWrapper.swift](/Users/uyakauleu/vivy/development/VivyTerm/VVTerm/Views/Terminal/SSHTerminalWrapper.swift)

Important distinction:
- Ghostty clipboard callbacks remain for terminal-native text copy/paste.
- Rich clipboard forwarding is an app-level feature above Ghostty.

### 2) Add a clipboard payload abstraction
Extend clipboard utilities to detect more than strings.

Proposed local model:
```swift
enum ClipboardPayload {
    case text(String)
    case image(data: Data, utType: String, suggestedExtension: String)
}
```

Platform behavior:
- macOS: inspect `NSPasteboard` for image representations, prefer PNG/TIFF input normalized to PNG or JPEG.
- iOS: inspect `UIPasteboard` for images, normalize to PNG or JPEG.

V1 supported rich payload:
- image only

Future:
- files
- PDFs
- multiple items

### 3) Add a remote upload service
Introduce a dedicated transfer component used by terminal sessions:

```swift
actor RemoteClipboardTransferService
```

Responsibilities:
- create a temporary remote file path
- upload clipboard image bytes to remote host

Introduce a separate orchestration component:

```swift
actor TerminalRichPasteCoordinator
```

Responsibilities:
- inspect clipboard payload
- invoke remote upload
- evaluate session capabilities
- drive fallback order
- return the final paste outcome to the terminal view layer

Proposed result:
```swift
struct RemoteClipboardAsset {
    let remotePath: String
    let mimeType: String
    let sizeBytes: Int
    let usedKittyClipboard: Bool
    let seededRemoteClipboard: Bool
}
```

Possible final outcome model:
```swift
enum RichPasteOutcome {
    case plainText
    case kittyClipboard
    case remoteClipboard
    case remotePath(String)
}
```

### 4) Transfer over SSH side channel, not terminal stdin
Use the existing SSH connection as a control/transfer channel.

V1 preferred implementation:
- add an SSH upload primitive in [SSHClient.swift](/Users/uyakauleu/vivy/development/VivyTerm/VVTerm/Services/SSH/SSHClient.swift)
- create remote directories with `execute(...)`
- transfer file bytes with a dedicated SFTP or SCP-style implementation

Why this is the right shape:
- avoids shell quoting problems for binary data
- avoids polluting interactive terminal state
- works even when the visible session is using Mosh
- gives deterministic success/failure boundaries
- lets remote TUIs continue using their normal clipboard-aware behavior
- allows a future protocol-native fast path without changing the core transfer architecture

Implementation preference:
1. SFTP upload if added cleanly to the existing libssh2 wrapper
2. SCP upload if simpler in current codebase
3. Exec-based base64 heredoc only as fallback, not preferred

The exec-based approach should be avoided as the primary upload design because it is slower, more fragile, and shell-dependent.

### 5) Temporary remote file placement
V1 should not use a durable clipboard directory as the primary storage location.

Preferred strategy:
- ask the remote host for a unique temp file with `mktemp`
- prefer `${TMPDIR}` when available, otherwise `/tmp`

Filename format:
```text
vvterm-clipboard-XXXXXX.{ext}
```

Example:
```text
/tmp/vvterm-clipboard-a1b2c3.png
```

Example command shape:
```sh
tmp_base="${TMPDIR:-/tmp}"; mktemp "${tmp_base%/}/vvterm-clipboard-XXXXXX.png"
```

Permissions:
- uploaded files should default to `0600`
- VVTerm should track and clean up files it created

Cleanup policy:
- delete on successful session-managed cleanup
- delete on disconnect when possible
- add a TTL sweep for leftovers, for example files older than 24 hours

Ownership:
- VVTerm should track temp files per `sessionId`
- `ConnectionSessionManager` should own normal lifecycle cleanup
- a best-effort background sweeper can remove stale VVTerm temp files left behind after crashes

### 6) Seed remote clipboard, then fall back to terminal text insertion
After upload succeeds, VVTerm should first attempt the richest supported paste mechanism for the current session.

Priority order:
1. Kitty `OSC 5522` rich clipboard path
2. remote machine clipboard seeding from temp file
3. terminal text insertion of temp file path

If Kitty `OSC 5522` succeeds:
- VVTerm should complete the paste in-app without requiring a second user gesture
- this is the most direct future path for clipboard-aware TUIs

If Kitty `OSC 5522` is unavailable or fails:
- VVTerm should attempt to populate the remote machine clipboard from the temporary file

If that succeeds:
- VVTerm should complete the paste in-app without requiring a second user gesture
- this preserves native TUI semantics for tools like Codex

If that fails:
- VVTerm should send only text into the active shell
- the inserted text should be the temporary remote file path

Default insertion:
- absolute remote path

Optional insertion styles:
- path only
- single-quoted path

V1 should not inject a trailing newline automatically.

Implementation note:
- the app-triggered paste step must avoid recursive re-entry into rich-paste routing
- a simple internal `pasteSource` flag such as `userInitiated` vs `programmaticAfterPreparation` is sufficient
- programmatic paste after successful Kitty or remote-clipboard preparation should bypass rich-paste detection and invoke the normal terminal paste path directly

Rationale:
- Kitty rich clipboard is the most semantically correct terminal-native protocol for image paste when available
- native remote clipboard behavior is the most semantically correct path for clipboard-aware TUIs
- avoids accidental command execution
- works for shells, editors, REPLs, and agent prompts
- lets the remote program decide how to consume the file

### 7) Mosh compatibility
For Mosh sessions:
- terminal interaction continues over Mosh
- rich clipboard upload still uses the retained SSH connection in `SSHClient`
- path insertion still goes through the visible active session

This matches the existing architecture, where Mosh already depends on SSH for bootstrap and management.

### 8) Remote clipboard seeding
Remote clipboard support is environment-dependent and must be capability-detected.

V1 target support:
- macOS remote hosts with `pbcopy`
- Linux hosts with `wl-copy` when Wayland clipboard access is available
- Linux hosts with `xclip` or `xsel` when X11 clipboard access is available

Likely unsupported in V1:
- headless Linux servers without GUI clipboard access
- minimal containers
- CI environments
- many Windows remotes

Important constraint:
- VVTerm must upload and seed the remote clipboard before invoking paste semantics in the terminal
- this cannot be deferred until after the TUI asks for clipboard contents

Recommended capability flow:
1. Detect remote platform via existing environment resolution.
2. Probe for a supported clipboard command.
3. Attempt clipboard seeding from the uploaded temp file.
4. If seeding succeeds, trigger normal paste.
5. Otherwise, fall back to path insertion.

Capability probing should be cached per session to avoid reprobe overhead on every paste.

Example command families:
- macOS:
```sh
osascript -e 'set the clipboard to (read (POSIX file "/tmp/vvterm-clipboard-a1b2c3.png") as PNG picture)'
```
- Linux Wayland:
```sh
wl-copy < /tmp/vvterm-clipboard-a1b2c3.png
```
- Linux X11:
```sh
xclip -selection clipboard -t image/png -i /tmp/vvterm-clipboard-a1b2c3.png
```

These should be treated as implementation examples, not a fixed final command set.

### 9) Future terminal-native path: Kitty `OSC 5522`
Kitty `OSC 5522` should be treated as a future fast path, not the baseline implementation.

Why:
- it is the right protocol for arbitrary clipboard MIME types such as `image/png`
- a remote TUI can request clipboard types and payloads directly
- it preserves true terminal-native paste semantics

Current constraints:
- Ghostty currently parses but does not fully implement Kitty `OSC 5522`
- remote TUIs must explicitly support the protocol
- Mosh should be treated as incompatible with this path

Architecture implication:
- VVTerm should model Kitty support as a capability on the session
- successful use of Kitty `OSC 5522` should bypass remote clipboard seeding
- the temp-file upload path should remain available because it is also the fallback input to remote system clipboard seeding and path insertion

Recommended gating:
- enable only for direct SSH sessions, not Mosh
- require explicit terminal capability confirmation
- fail fast into remote clipboard seeding if any negotiation step is missing

Capability probing for Kitty support should also be cached per session.

## Failure Handling

### If upload fails
- do not paste anything
- show concise error with retry action

Examples:
- `Remote upload failed: could not create temporary file`
- `Remote upload failed: connection unavailable`
- `Remote upload failed: file transfer not supported for this session`

### If remote clipboard seeding fails
- do not fail the entire operation by default
- fall back to inserting the temporary remote file path
- show concise status such as `Remote clipboard unavailable, pasted temp file path instead`

### If Kitty `OSC 5522` fails
- do not fail the entire operation by default
- fall back to remote clipboard seeding
- if remote clipboard seeding also fails, fall back to temp file path insertion
- show concise status such as `Terminal rich clipboard unavailable, used remote clipboard fallback`

### If clipboard contains both text and image
Behavior in `Ask` mode:
- offer both options

Behavior in `Auto` mode:
- prefer image upload if a supported image item exists

### If the remote platform is unsupported
V1 should target POSIX-style remote hosts first.

For Windows SSH targets:
- either disable rich paste in V1
- or use a separate `%USERPROFILE%\\.vvterm\\clipboard` path design in V2

Recommended V1 decision:
- POSIX remote hosts only
- surface unsupported-platform message for Windows

## Security Considerations
- Do not silently upload clipboard images when the feature is `Off`.
- `Ask` mode is the safest first-release default because image clipboard often contains sensitive screenshots.
- Never echo raw image bytes into terminal output.
- Prefer user-private temp files where possible and avoid durable storage by default.
- Do not auto-delete files immediately after paste; users need stable paths.
- Consider a future cleanup policy for aged files.

## Performance Expectations
- Clipboard inspection should be synchronous and fast.
- Image normalization should happen locally before upload.
- Upload should run off the main actor with progress reporting.
- Large image uploads should show progress and allow cancel.

Reasonable V1 constraints:
- soft warning above 10 MB
- hard failure above a configurable safety cap, for example 50 MB

## Testing Plan

### Unit tests
- Clipboard payload detection for text vs image.
- Remote path generation and file naming.
- Insert style formatting.
- Unsupported platform gating.

### Integration tests
- Text paste remains unchanged.
- Kitty `OSC 5522` path is attempted only when capability detection says it is available.
- Kitty `OSC 5522` failure falls back cleanly to remote clipboard seeding.
- Image paste uploads file, seeds remote clipboard, and triggers native paste when supported.
- Image paste falls back to temp file path insertion when remote clipboard is unsupported.
- Failure to create temp file surfaces error without input injection.
- Mosh session image paste still uploads through SSH.
- Mosh sessions skip Kitty `OSC 5522` entirely.

### Manual tests
- macOS local screenshot paste into remote shell prompt.
- iOS photo clipboard paste into remote shell prompt.
- Direct SSH session with a Kitty-clipboard-aware TUI once Ghostty support exists.
- Paste image into Codex CLI session on a remote host with clipboard support and confirm native paste works.
- Paste image into Codex CLI session on a headless remote host and confirm temp-path fallback is usable.
- Clipboard containing both copied text and screenshot.
- Repeated pastes produce unique files.
- Temp files are cleaned up on normal session shutdown.

## Rollout
1. Add behind feature flag: `richClipboardPasteEnabled`
2. Ship `Ask` mode by default
3. Observe upload reliability and user behavior
4. Consider `Auto` default after validation

## Open Questions
- Should V1 support only images, or images plus arbitrary files from the clipboard/share sheet?
- Should uploaded files be cleaned up automatically after N days?
- Should VVTerm offer a dedicated `Paste Image` action in the keyboard toolbar on iOS?
- Should we add app-specific insertion adapters later for tools like Codex, Claude Code, or Gemini CLI?
- Is SCP easier to land quickly than SFTP in the current libssh2 wrapper, and is that acceptable for V1?
- How should VVTerm detect future Ghostty `OSC 5522` support reliably from the embedded runtime?

## Recommended V1 Decision
Implement image-only rich clipboard paste as:
- app-level clipboard detection
- SSH side-channel upload to a temporary remote file
- future Kitty `OSC 5522` fast path when terminal/runtime support exists
- remote clipboard seeding when supported
- normal paste semantics after either successful clipboard path
- plain-text temp-path fallback when remote clipboard seeding is unavailable

This is the simplest design that is technically correct, useful for agent workflows, and consistent with how terminals and SSH actually work.
