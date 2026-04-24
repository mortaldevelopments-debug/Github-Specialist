--!strict

--- Client entry-point script.
--- Bootstraps all client-side controllers after the local player is fully loaded.
--- This file maps to StarterPlayerScripts via the Rojo project file.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script:WaitForChild("Controllers")

local UIController = require(Controllers:WaitForChild("UIController"))

local localPlayer = Players.LocalPlayer

-- Wait for character to be ready before starting controllers.
if not localPlayer.Character then
    localPlayer.CharacterAdded:Wait()
end

local uiController = UIController.new(localPlayer)
uiController:start()

print("[Client] All controllers initialized successfully")
