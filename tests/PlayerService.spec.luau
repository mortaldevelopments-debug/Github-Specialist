--!strict

--- @testmodule PlayerService
--- TestEZ specification for the PlayerService module.
--- Run inside Roblox Studio with a TestEZ runner (server context required).
---
--- These tests focus on the pure business logic of PlayerService
--- (coin validation, level computation) using a stub PlayerData object.

return function()
    local ServerScriptService = game:GetService("ServerScriptService")
    local PlayerService = require(ServerScriptService.Services.PlayerService)

    -- Build a minimal fake Player object for testing purposes.
    local function makeFakePlayer(userId: number, displayName: string): Player
        return {
            UserId = userId,
            DisplayName = displayName,
        } :: any
    end

    -- Directly inject stub data so we don't depend on DataStores.
    local function makeService()
        local svc = PlayerService.new()
        return svc
    end

    local function injectData(svc: any, player: Player, data: any)
        svc._playerData[player.UserId] = data
    end

    describe("PlayerService:addCoins", function()
        it("should add coins to a player's balance", function()
            local svc = makeService()
            local player = makeFakePlayer(1, "TestUser")
            injectData(svc, player, {
                userId = 1,
                displayName = "TestUser",
                coins = 100,
                level = 1,
                experience = 0,
                joinedAt = 0,
            })
            local ok = svc:addCoins(player, 50)
            expect(ok).to.equal(true)
            expect(svc._playerData[1].coins).to.equal(150)
        end)

        it("should cap coins at MAX_COINS (1,000,000)", function()
            local svc = makeService()
            local player = makeFakePlayer(2, "RichUser")
            injectData(svc, player, {
                userId = 2,
                displayName = "RichUser",
                coins = 999_990,
                level = 1,
                experience = 0,
                joinedAt = 0,
            })
            svc:addCoins(player, 100)
            expect(svc._playerData[2].coins).to.equal(1_000_000)
        end)

        it("should reject non-number amounts", function()
            local svc = makeService()
            local player = makeFakePlayer(3, "BadActor")
            injectData(svc, player, {
                userId = 3,
                displayName = "BadActor",
                coins = 0,
                level = 1,
                experience = 0,
                joinedAt = 0,
            })
            local ok = svc:addCoins(player, "lots" :: any)
            expect(ok).to.equal(false)
        end)

        it("should reject zero and negative amounts", function()
            local svc = makeService()
            local player = makeFakePlayer(4, "NegativeUser")
            injectData(svc, player, {
                userId = 4,
                displayName = "NegativeUser",
                coins = 50,
                level = 1,
                experience = 0,
                joinedAt = 0,
            })
            expect(svc:addCoins(player, 0)).to.equal(false)
            expect(svc:addCoins(player, -10)).to.equal(false)
            expect(svc._playerData[4].coins).to.equal(50)
        end)

        it("should reject fractional amounts", function()
            local svc = makeService()
            local player = makeFakePlayer(5, "FloatUser")
            injectData(svc, player, {
                userId = 5,
                displayName = "FloatUser",
                coins = 0,
                level = 1,
                experience = 0,
                joinedAt = 0,
            })
            local ok = svc:addCoins(player, 1.5)
            expect(ok).to.equal(false)
        end)

        it("should return false when player data is not loaded", function()
            local svc = makeService()
            local player = makeFakePlayer(99, "Ghost")
            local ok = svc:addCoins(player, 10)
            expect(ok).to.equal(false)
        end)
    end)

    describe("PlayerService:addExperience", function()
        it("should add experience to a player", function()
            local svc = makeService()
            local player = makeFakePlayer(10, "ExpUser")
            injectData(svc, player, {
                userId = 10,
                displayName = "ExpUser",
                coins = 0,
                level = 1,
                experience = 0,
                joinedAt = 0,
            })
            local ok = svc:addExperience(player, 100)
            expect(ok).to.equal(true)
            expect(svc._playerData[10].experience).to.equal(100)
        end)

        it("should level up the player when experience crosses a threshold", function()
            local svc = makeService()
            local player = makeFakePlayer(11, "LevelUpUser")
            injectData(svc, player, {
                userId = 11,
                displayName = "LevelUpUser",
                coins = 0,
                level = 1,
                experience = 90,
                joinedAt = 0,
            })
            svc:addExperience(player, 20) -- crosses 100 threshold
            expect(svc._playerData[11].level).to.be.ok()
            expect(svc._playerData[11].level).to.equal(2)
        end)
    end)

    describe("PlayerService:getPlayerData", function()
        it("should return nil for unknown players", function()
            local svc = makeService()
            local player = makeFakePlayer(999, "Unknown")
            expect(svc:getPlayerData(player)).to.equal(nil)
        end)

        it("should return data after injection", function()
            local svc = makeService()
            local player = makeFakePlayer(20, "KnownUser")
            local data = {
                userId = 20,
                displayName = "KnownUser",
                coins = 500,
                level = 3,
                experience = 300,
                joinedAt = 0,
            }
            injectData(svc, player, data)
            expect(svc:getPlayerData(player)).to.equal(data)
        end)
    end)
end
