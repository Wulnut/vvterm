# Windows Native UI + Swift Core FFI Bridge (Draft Idea Backlog)

## Summary
Explore a future Windows version of VVTerm that keeps the UI fully native with WinUI while moving shared connection and session logic into a headless Swift core exposed through a small C ABI / FFI bridge.

Draft date: 2026-03-08

Status: Backlog idea only. This is not an approved roadmap item.

## Problem
VVTerm is currently shaped around Apple platforms. The app lifecycle, UI shell, terminal embedding, secure storage, sync, purchases, biometrics, and several UX flows are tightly coupled to Apple frameworks and Apple runtime assumptions.

That makes a direct Windows port unattractive:
- Reusing the current SwiftUI/AppKit/UIKit surface would not feel native on Windows.
- Rewriting the entire app natively for Windows would duplicate a large amount of session and connection logic.
- A broad "Swift multiplatform" approach would still leave the most important product layers platform-specific.

## Idea
Build a Windows app as a native WinUI client and treat the reusable Swift code as a headless engine.

The engine would:
- own server/workspace/session models
- own SSH/session orchestration
- own terminal byte-stream and connection state logic
- expose a small stable C ABI

The Windows app would:
- render all UI with WinUI
- own Windows-native UX and system integration
- call into the Swift core through FFI
- provide platform-specific services back to the core when needed

## Goals
- Preserve a native Windows UI and platform feel.
- Minimize duplication of SSH/session/domain logic.
- Keep the bridge small enough to stay maintainable.
- Keep latency low by using in-process FFI instead of a separate helper process.
- Refactor the current Apple codebase toward a headless reusable core over time.

## Non-Goals
- A near-term commitment to ship Windows.
- Reusing the current Apple UI on Windows.
- Full feature parity in V1 of any future Windows app.
- A single shared multiplatform UI layer.
- Exposing raw Swift types directly to Windows code.

## Why FFI Instead Of IPC
This idea assumes FFI is the preferred bridge if work ever starts.

Reasons:
- in-process calls avoid helper-process lifecycle complexity
- lower latency for terminal/session interactions
- small intended API surface
- no extra transport/protocol layer unless future needs force one

Tradeoff:
- ABI and memory management discipline becomes critical

## Proposed Architecture

### High-level split
- `VVTermCore`
  - pure/headless Swift module
  - no SwiftUI, AppKit, UIKit, CloudKit, StoreKit, Security, Metal, ActivityKit, or LocalAuthentication imports
- `VVTermApple`
  - current Apple app shell and platform adapters
- `VVTermWindows`
  - future WinUI app shell and Windows adapters
- `VVTermCoreBridge`
  - narrow C ABI wrapper around `VVTermCore`

### Responsibilities

#### Core owns
- server/workspace/session data models
- connection lifecycle
- SSH orchestration
- terminal I/O model
- connection state/events
- config and business rules
- DTOs used by the bridge

#### Platform app owns
- native UI
- windowing/navigation
- terminal rendering widget
- secure storage implementation
- sync backend implementation
- purchase/store implementation
- biometrics implementation
- notifications and OS integrations

## Dependency Inversion Strategy
Platform-dependent services should be represented as capabilities, not Apple framework calls.

Examples:
- `SecretStore`
- `SyncBackend`
- `PurchaseBackend`
- `BiometricBackend`
- `HostEnvironment`

The core should say:
- "load secret for server X"
- "save server Y"
- "report entitlement state"

The core should never say:
- "read from Keychain"
- "save to CloudKit"
- "call StoreKit"

## FFI Boundary Design
The FFI boundary should be intentionally small and C-shaped.

Allowed across the boundary:
- opaque handles
- integers/bools
- UTF-8 strings
- byte buffers
- JSON DTO payloads
- callback function pointers

Avoid across the boundary:
- Swift structs/enums directly
- reference graphs
- Swift async functions directly
- platform framework objects

### Suggested boundary style
- top-level core handle
- per-session opaque handles
- event callback registration
- JSON for structured requests/responses
- explicit free functions for memory returned to host

## Draft API Shape

### Core lifecycle
- `vvterm_core_create`
- `vvterm_core_destroy`
- `vvterm_core_set_event_callback`
- `vvterm_core_set_host_callbacks`

### Server and workspace operations
- `vvterm_core_list_servers_json`
- `vvterm_core_save_server_json`
- `vvterm_core_delete_server`
- `vvterm_core_list_workspaces_json`

### Session operations
- `vvterm_core_connect_json`
- `vvterm_core_disconnect`
- `vvterm_core_send_input`
- `vvterm_core_resize`
- `vvterm_core_send_signal`

### Utility
- `vvterm_string_free`
- `vvterm_buffer_free`
- `vvterm_last_error_message`

## Example C ABI Sketch
```c
typedef void* VVTermCoreHandle;
typedef void* VVTermSessionHandle;

typedef void (*vvterm_event_callback)(
    const char* event_name,
    const char* event_json,
    void* context
);

VVTermCoreHandle vvterm_core_create(void);
void vvterm_core_destroy(VVTermCoreHandle core);

void vvterm_core_set_event_callback(
    VVTermCoreHandle core,
    vvterm_event_callback callback,
    void* context
);

char* vvterm_core_list_servers_json(VVTermCoreHandle core);
VVTermSessionHandle vvterm_core_connect_json(VVTermCoreHandle core, const char* request_json);
void vvterm_core_send_input(VVTermSessionHandle session, const uint8_t* bytes, int length);
void vvterm_core_resize(VVTermSessionHandle session, int cols, int rows);
void vvterm_core_disconnect(VVTermSessionHandle session);
void vvterm_string_free(char* value);
```

## Example Host Callback Direction
One likely pattern is for the Windows app to provide platform services back into the core.

Example callback needs:
- load secret for server ID
- save/delete secret for server ID
- fetch/store synced metadata
- report entitlement state
- request biometric unlock if platform supports it
- persist local settings

This keeps Windows-native API usage on the Windows side while allowing the Swift core to stay platform-neutral.

## Example DTOs
```swift
public struct ServerDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
}

public struct ConnectRequestDTO: Codable, Sendable {
    public var serverID: UUID
    public var cols: Int
    public var rows: Int
}

public struct TerminalOutputEventDTO: Codable, Sendable {
    public var sessionID: UUID
    public var dataBase64: String
}
```

## Refactor Direction In Current Repo
If this idea is pursued later, the first refactor should be to extract headless logic from the current app instead of trying to bridge existing Apple-shaped managers directly.

Probable extraction candidates:
- `Models/`
- parts of `Services/SSH/`
- session lifecycle logic from `Managers/ConnectionSessionManager.swift`
- parsers and terminal state glue that do not depend on Apple views

Probable Apple-only layers to keep out of core:
- `Services/CloudKit/CloudKitManager.swift`
- `Services/Keychain/KeychainManager.swift`
- `Services/Store/StoreManager.swift`
- `Services/Security/BiometricAuthService.swift`
- `GhosttyTerminal/*View*`
- app/window/UI code in SwiftUI/AppKit/UIKit

## Windows App Direction
If a Windows version ever starts, it should target native Windows UI rather than trying to preserve the Apple visual structure.

Assumptions:
- WinUI 3 for the app shell
- Windows-native settings/forms/navigation
- Windows-native title bar, dialogs, menus, and window behavior
- Windows-native secure storage and system prompts
- separate Windows terminal host/rendering layer

## Major Risks
- The current codebase may require substantial refactoring before a stable core can exist.
- Terminal integration may remain the hardest part even with a shared core.
- Async/event-heavy session logic can become brittle if callback and threading rules are not explicit.
- Swift on Windows toolchain and packaging constraints may shape feasibility.
- A small bridge can gradually grow into an overly chatty interface if not enforced.

## Guardrails If Work Ever Starts
- Keep the FFI API intentionally small.
- Prefer coarse-grained events and payloads over many tiny synchronous calls.
- Use opaque handles and DTOs only.
- Make ownership and free rules explicit in the ABI.
- Keep platform-specific services outside the core.
- Do not move Apple-only features into the first shared-core pass unless there is proven payoff.

## Suggested Milestones

### Milestone 0: Investigation spike
- validate Swift-on-Windows toolchain constraints
- validate DLL export story for Swift core
- validate WinUI P/Invoke integration with a tiny prototype

### Milestone 1: Core extraction
- extract headless server/session/domain logic into `VVTermCore`
- remove Apple framework dependencies from the extracted layer

### Milestone 2: Minimal bridge
- create `VVTermCoreBridge` with create/destroy/list/connect/send/resize/disconnect
- emit terminal output and connection-state events through callback

### Milestone 3: Host services
- define host callback table for secrets/settings/sync adapters
- wire Apple app through same abstractions where practical

### Milestone 4: Windows prototype
- WinUI shell
- native list/detail flows
- one working terminal/session path

## Open Questions
- Is Swift-on-Windows mature enough for the required packaging and debugging story?
- Should the first shared core exclude sync, purchases, and biometrics entirely?
- Should the Windows app own more business logic initially to reduce bridge complexity?
- Is the terminal host best treated as fully platform-owned with only byte-stream/session control in core?
- Is the future bridge best kept synchronous where possible, or should it be event-first from day one?

## Recommendation
If this backlog item is ever revisited, start with a technical spike and treat the bridge as an engineering experiment, not a product commitment.

The path only makes sense if all of the following stay true:
- Windows UI must remain fully native
- the shared API can remain small
- a headless Swift core can be extracted cleanly
- the bridge actually reduces long-term duplication instead of spreading complexity across two runtimes
