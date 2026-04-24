--!strict

--- @class Net
--- Utility module for creating and managing RemoteEvents and RemoteFunctions.
--- Enforces server-side validation patterns and consistent naming conventions.
---
--- 🔴 Security rule: NEVER trust client-supplied data.
--- All `onServerEvent` handlers should validate their arguments before use.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

local Net = {}

-- ── Internal helpers ────────────────────────────────────────────────────────

--- Gets or creates a RemoteEvent under ReplicatedStorage.
--- @param name string -- Unique identifier for the remote.
--- @return RemoteEvent
local function getOrCreateRemote(name: string): RemoteEvent
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        return existing
    end
    if IS_SERVER then
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = ReplicatedStorage
        return remote
    else
        return ReplicatedStorage:WaitForChild(name) :: RemoteEvent
    end
end

--- Gets or creates a RemoteFunction under ReplicatedStorage.
--- @param name string -- Unique identifier for the remote function.
--- @return RemoteFunction
local function getOrCreateRemoteFunction(name: string): RemoteFunction
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then
        return existing
    end
    if IS_SERVER then
        local remote = Instance.new("RemoteFunction")
        remote.Name = name
        remote.Parent = ReplicatedStorage
        return remote
    else
        return ReplicatedStorage:WaitForChild(name) :: RemoteFunction
    end
end

-- ── Client → Server ─────────────────────────────────────────────────────────

--- Fires a RemoteEvent from the client to the server.
--- @param name string -- Remote name.
--- @param ... any -- Arguments forwarded to the server handler.
function Net.fireServer(name: string, ...)
    assert(not IS_SERVER, "[Net] fireServer must be called from the client")
    getOrCreateRemote(name):FireServer(...)
end

-- ── Server → Client ─────────────────────────────────────────────────────────

--- Fires a RemoteEvent from the server to a specific client.
--- @param name string -- Remote name.
--- @param player Player -- Target player.
--- @param ... any -- Arguments forwarded to the client handler.
function Net.fireClient(name: string, player: Player, ...)
    assert(IS_SERVER, "[Net] fireClient must be called from the server")
    getOrCreateRemote(name):FireClient(player, ...)
end

--- Fires a RemoteEvent from the server to all connected clients.
--- @param name string -- Remote name.
--- @param ... any -- Arguments forwarded to all client handlers.
function Net.fireAllClients(name: string, ...)
    assert(IS_SERVER, "[Net] fireAllClients must be called from the server")
    getOrCreateRemote(name):FireAllClients(...)
end

-- ── Handler registration ─────────────────────────────────────────────────────

--- Registers a server-side handler for a RemoteEvent.
--- The handler is wrapped in `pcall` to prevent server crashes from malformed client payloads.
---
--- 🔴 Critical: Always validate `player` and all arguments inside `handler`.
--- @param name string -- Remote name.
--- @param handler (player: Player, ...any) -> () -- Callback invoked on each client fire.
--- @return RBXScriptConnection
function Net.onServerEvent(name: string, handler: (player: Player, ...any) -> ()): RBXScriptConnection
    assert(IS_SERVER, "[Net] onServerEvent must be called from the server")
    return getOrCreateRemote(name).OnServerEvent:Connect(function(player, ...)
        -- 🔴 Critical: Wrap in pcall so a bad payload cannot crash the server.
        local ok, err = pcall(handler, player, ...)
        if not ok then
            warn(`[Net] Handler "{name}" errored for {player.DisplayName}: {err}`)
        end
    end)
end

--- Registers a client-side handler for a RemoteEvent.
--- @param name string -- Remote name.
--- @param handler (...any) -> () -- Callback invoked when the server fires the remote.
--- @return RBXScriptConnection
function Net.onClientEvent(name: string, handler: (...any) -> ()): RBXScriptConnection
    assert(not IS_SERVER, "[Net] onClientEvent must be called from the client")
    return getOrCreateRemote(name).OnClientEvent:Connect(handler)
end

--- Registers a server-side handler for a RemoteFunction (invoke/callback pattern).
--- @param name string -- Remote function name.
--- @param handler (player: Player, ...any) -> ...any
function Net.onServerInvoke(name: string, handler: (player: Player, ...any) -> ...any)
    assert(IS_SERVER, "[Net] onServerInvoke must be called from the server")
    getOrCreateRemoteFunction(name).OnServerInvoke = function(player, ...)
        -- 🔴 Critical: Wrap handler to prevent server crashes.
        local ok, result = pcall(handler, player, ...)
        if not ok then
            warn(`[Net] RemoteFunction "{name}" errored for {player.DisplayName}: {result}`)
            return nil
        end
        return result
    end
end

--- Invokes a RemoteFunction from the client, yielding until the server responds.
--- @param name string -- Remote function name.
--- @param ... any -- Arguments forwarded to the server.
--- @return any -- The value returned by the server handler.
function Net.invokeServer(name: string, ...): any
    assert(not IS_SERVER, "[Net] invokeServer must be called from the client")
    return getOrCreateRemoteFunction(name):InvokeServer(...)
end

return Net
