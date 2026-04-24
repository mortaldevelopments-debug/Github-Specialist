--!strict

--- Server entry-point script.
--- Bootstraps all server-side services in dependency order.
--- This file maps to ServerScriptService via the Rojo project file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script:WaitForChild("Services")

local DataService = require(Services:WaitForChild("DataService"))
local PlayerService = require(Services:WaitForChild("PlayerService"))

-- Boot sequence: DataService first so PlayerService can reference it if needed.
local dataService = DataService.new()
local playerService = PlayerService.new()

playerService:start()

print("[Server] All services initialized successfully")

-- Expose services to other server scripts via a shared table (optional pattern).
-- Other Scripts under ServerScriptService can do:
--   local Services = require(game.ServerScriptService.init)
--   Services.PlayerService:getPlayerData(player)
return {
    DataService = dataService,
    PlayerService = playerService,
}
