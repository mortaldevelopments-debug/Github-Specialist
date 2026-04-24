# Github-Specialist

A professional Roblox game development repository demonstrating best-practice
**Luau** architecture, strict typing, modular game systems, and a GitHub Actions
CI pipeline for automated linting and format checking.

---

## Project structure

```
default.project.json          Rojo project file (syncs to Roblox Studio)
aftman.toml                   Toolchain pinned versions (StyLua, Selene, Rojo)
selene.toml                   Selene linter configuration
stylua.toml                   StyLua formatter configuration
src/
  server/
    init.server.luau          Server entry-point – bootstraps all services
    Services/
      PlayerService.luau      Player lifecycle, coin/XP management, validation
      DataService.luau        DataStoreService wrapper with retry logic
  shared/
    Types.luau                Exported Luau types shared across server & client
    Modules/
      Maid.luau               Cleanup utility – prevents memory leaks
      Signal.luau             Typed custom event emitter
      Net.luau                RemoteEvent/RemoteFunction helpers
  client/
    init.client.luau          Client entry-point – bootstraps all controllers
    Controllers/
      UIController.luau       HUD management and server-push event handling
tests/
  Signal.spec.luau            TestEZ specs for Signal
  Maid.spec.luau              TestEZ specs for Maid
  PlayerService.spec.luau     TestEZ specs for PlayerService business logic
```

## Key design principles

| Principle | Implementation |
|---|---|
| `--!strict` typing | Every file opts in to full Luau type checking |
| Single Responsibility | Each module owns exactly one concern |
| Server-side validation | All `RemoteEvent` payloads validated before state mutation |
| Memory management | `Maid` tracks connections/instances; `destroy()` always cleans up |
| OOP with metatables | `__index` pattern used throughout; no globals |
| Modern task API | `task.spawn`, `task.defer`, `task.wait` replace deprecated `spawn`/`wait` |
| Moonwave/LDoc comments | Every public function has `@param`/`@return` annotations |

## CI pipeline

Every push and pull request runs:

1. **StyLua** – enforces consistent formatting (`stylua --check`)
2. **Selene** – static analysis against the `roblox` standard library

## Running tests

Tests are written with the **TestEZ** framework and run inside Roblox Studio:

1. Sync the project with `rojo serve` → connect in Studio.
2. Place a `Script` in `ServerScriptService` that requires `TestEZ` and calls  
   `TestEZ.TestBootstrap:run({ game.ReplicatedStorage.tests })`.

## Syncing to Roblox Studio (Rojo)

```bash
# Install tools
aftman install

# Start the Rojo dev server
rojo serve default.project.json
```

Then connect with the **Rojo** Studio plugin to sync source files in real time.

## Code review conventions

When reviewing Luau code in this repository, categorise feedback as:

- 🔴 **Critical** – logic errors, security flaws (e.g. missing server-side validation), memory leaks
- 🟡 **Warning** – performance issues, code smells, deprecated API usage
- 🔵 **Suggestion** – readability improvements, additional Luau type hints

