--!strict

--- @class PlayerService
--- Manages the full player lifecycle: join, data loading, leave, and data saving.
--- Exposes typed signals so other systems can react to player events without tight coupling.
---
--- All RemoteEvent payloads are validated server-side before any state mutation.
--- Memory is managed with a `Maid` so connections are never leaked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Modules:WaitForChild("Maid"))
local Signal = require(Modules:WaitForChild("Signal"))
local Net = require(Modules:WaitForChild("Net"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type PlayerData = Types.PlayerData

-- Experience required to reach each level (index = level).
local LEVEL_THRESHOLDS: { number } = { 0, 100, 250, 500, 1_000, 2_000, 5_000, 10_000 }
local MAX_COINS: number = 1_000_000
local MAX_COIN_GRANT: number = 10_000 -- 🔴 Server-side cap per single grant call.

local PlayerService = {}
PlayerService.__index = PlayerService

export type PlayerServiceObject = {
    --- Fires `(player: Player, data: PlayerData)` when a player's data is ready.
    playerAdded: any,
    --- Fires `(player: Player, data: PlayerData)` just before player data is saved and removed.
    playerRemoving: any,
    start: (self: PlayerServiceObject) -> (),
    getPlayerData: (self: PlayerServiceObject, player: Player) -> PlayerData?,
    addCoins: (self: PlayerServiceObject, player: Player, amount: number) -> boolean,
    addExperience: (self: PlayerServiceObject, player: Player, amount: number) -> boolean,
    destroy: (self: PlayerServiceObject) -> (),
}

--- Creates a new PlayerService instance.
--- Call `start()` after construction to begin listening for player events.
--- @return PlayerServiceObject
function PlayerService.new(): PlayerServiceObject
    local self = setmetatable({
        _maid = Maid.new(),
        _playerData = {} :: { [number]: PlayerData },
        playerAdded = Signal.new(),
        playerRemoving = Signal.new(),
    }, PlayerService)
    return self :: any
end

--- Starts the service: hooks into `Players.PlayerAdded/Removing` and registers
--- the server-side `AddCoins` RemoteEvent handler.
function PlayerService:start()
    self._maid:giveTask(Players.PlayerAdded:Connect(function(player)
        self:_onPlayerAdded(player)
    end))

    self._maid:giveTask(Players.PlayerRemoving:Connect(function(player)
        self:_onPlayerRemoving(player)
    end))

    -- 🔴 Critical: Validate all fields in the RemoteEvent payload server-side.
    self._maid:giveTask(Net.onServerEvent("AddCoins", function(player: Player, amount: any)
        if type(amount) ~= "number" then
            warn(`[PlayerService] AddCoins: invalid amount type from {player.DisplayName}`)
            return
        end
        self:addCoins(player, amount)
    end))

    -- Handle players who joined before this service started.
    for _, player in Players:GetPlayers() do
        task.spawn(function()
            self:_onPlayerAdded(player)
        end)
    end
end

-- ── Private methods ──────────────────────────────────────────────────────────

--- @private
function PlayerService:_onPlayerAdded(player: Player)
    local data = self:_loadPlayerData(player)
    self._playerData[player.UserId] = data
    self.playerAdded:fire(player, data)
end

--- @private
function PlayerService:_onPlayerRemoving(player: Player)
    local data = self._playerData[player.UserId]
    if data then
        self.playerRemoving:fire(player, data)
        -- Use task.defer so other PlayerRemoving listeners still get the data.
        task.defer(function()
            self:_savePlayerData(player, data)
            self._playerData[player.UserId] = nil
        end)
    end
end

--- @private
--- Loads player data from the DataStore. Falls back to default data on failure.
--- @param player Player
--- @return PlayerData
function PlayerService:_loadPlayerData(player: Player): PlayerData
    -- DataStore call would go here (wrapped in pcall with retry logic).
    -- Returning default data for now to keep the example runnable.
    return {
        userId = player.UserId,
        displayName = player.DisplayName,
        coins = 0,
        level = 1,
        experience = 0,
        joinedAt = os.time(),
    }
end

--- @private
--- Persists player data to the DataStore using a deferred task to avoid blocking.
--- @param player Player
--- @param data PlayerData
function PlayerService:_savePlayerData(_player: Player, _data: PlayerData)
    -- DataStoreService:GetDataStore("PlayerData"):SetAsync(tostring(player.UserId), data)
    -- Wrapped in pcall + retry logic (see DataService for the shared implementation).
end

--- @private
--- Computes the player's level from their total experience.
--- @param experience number
--- @return number
function PlayerService:_computeLevel(experience: number): number
    local level = 1
    for i, threshold in LEVEL_THRESHOLDS do
        if experience >= threshold then
            level = i
        end
    end
    return level
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Returns the cached `PlayerData` for `player`, or `nil` if not yet loaded.
--- @param player Player
--- @return PlayerData?
function PlayerService:getPlayerData(player: Player): PlayerData?
    return self._playerData[player.UserId]
end

--- Adds `amount` coins to `player`'s balance with full server-side validation.
--- Returns `false` (and warns) if the input is invalid.
---
--- 🔴 Critical: This is the authoritative coins mutation path.
---              Never modify coins directly from RemoteEvent payloads.
--- @param player Player
--- @param amount number -- Must be a positive integer ≤ MAX_COIN_GRANT.
--- @return boolean -- `true` on success.
function PlayerService:addCoins(player: Player, amount: number): boolean
    if type(amount) ~= "number" or amount ~= math.floor(amount) or amount <= 0 then
        warn(`[PlayerService] addCoins: invalid amount ({amount}) for {player.DisplayName}`)
        return false
    end

    if amount > MAX_COIN_GRANT then
        warn(`[PlayerService] addCoins: amount {amount} exceeds cap for {player.DisplayName}`)
        return false
    end

    local data = self._playerData[player.UserId]
    if not data then
        warn(`[PlayerService] addCoins: no data found for {player.DisplayName}`)
        return false
    end

    data.coins = math.min(data.coins + amount, MAX_COINS)

    -- Notify the specific client of their updated balance.
    Net.fireClient("CoinsUpdated", player, data.coins)
    return true
end

--- Adds `amount` experience to `player` and recalculates their level.
--- @param player Player
--- @param amount number -- Must be a positive integer.
--- @return boolean -- `true` on success.
function PlayerService:addExperience(player: Player, amount: number): boolean
    if type(amount) ~= "number" or amount ~= math.floor(amount) or amount <= 0 then
        warn(`[PlayerService] addExperience: invalid amount ({amount}) for {player.DisplayName}`)
        return false
    end

    local data = self._playerData[player.UserId]
    if not data then
        return false
    end

    data.experience += amount
    local newLevel = self:_computeLevel(data.experience)
    if newLevel ~= data.level then
        data.level = newLevel
        Net.fireClient("LevelUp", player, newLevel)
    end

    return true
end

--- Destroys the PlayerService, cleaning up all event connections and signals.
function PlayerService:destroy()
    self._maid:destroy()
    self.playerAdded:destroy()
    self.playerRemoving:destroy()
end

return PlayerService
