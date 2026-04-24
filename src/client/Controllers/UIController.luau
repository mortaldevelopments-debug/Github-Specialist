--!strict

--- @class UIController
--- Manages UI updates and HUD interactions for the local player.
--- Listens for server-pushed events (`CoinsUpdated`, `LevelUp`, `DataUpdated`)
--- and updates the player's `PlayerGui` accordingly.
---
--- Memory is managed with a `Maid` so all connections are cleaned on `destroy()`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Modules:WaitForChild("Maid"))
local Signal = require(Modules:WaitForChild("Signal"))
local Net = require(Modules:WaitForChild("Net"))

local UIController = {}
UIController.__index = UIController

export type UIControllerObject = {
    --- Fires `(data: {[string]: any})` whenever the server pushes a full data update.
    onDataUpdated: any,
    start: (self: UIControllerObject) -> (),
    destroy: (self: UIControllerObject) -> (),
}

--- Creates a new UIController for `player`.
--- @param player Player -- The local player.
--- @return UIControllerObject
function UIController.new(player: Player): UIControllerObject
    return setmetatable({
        _player = player,
        _maid = Maid.new(),
        onDataUpdated = Signal.new(),
    }, UIController) :: any
end

--- Starts the controller, connecting it to all relevant server RemoteEvents.
function UIController:start()
    -- Full data refresh (e.g. on first load).
    self._maid:giveTask(Net.onClientEvent("DataUpdated", function(data: { [string]: any })
        self.onDataUpdated:fire(data)
        self:_updateUI(data)
    end))

    -- Incremental coin balance update.
    self._maid:giveTask(Net.onClientEvent("CoinsUpdated", function(coins: number)
        self:_updateCoinsDisplay(coins)
    end))

    -- Level-up notification.
    self._maid:giveTask(Net.onClientEvent("LevelUp", function(newLevel: number)
        self:_showLevelUpNotification(newLevel)
    end))
end

-- ── Private helpers ──────────────────────────────────────────────────────────

--- @private
--- Applies a full data payload to all HUD elements.
--- @param data {[string]: any}
function UIController:_updateUI(data: { [string]: any })
    local playerGui = self._player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end
    -- Individual HUD update calls would go here, e.g.:
    -- self:_updateCoinsDisplay(data.coins)
    -- self:_updateLevelDisplay(data.level)
end

--- @private
--- Updates the coins label in the HUD.
--- @param coins number
function UIController:_updateCoinsDisplay(coins: number)
    local playerGui = self._player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end
    -- Example path: playerGui.HUD.CoinsLabel.Text = `🪙 {coins}`
end

--- @private
--- Shows a brief level-up notification.
--- @param newLevel number
function UIController:_showLevelUpNotification(newLevel: number)
    local playerGui = self._player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end
    -- Example: tween in a "Level {newLevel}!" banner and fade it out.
end

--- Destroys the UIController, disconnecting all event listeners and signals.
function UIController:destroy()
    self._maid:destroy()
    self.onDataUpdated:destroy()
end

return UIController
