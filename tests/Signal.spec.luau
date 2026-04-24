--!strict

--- @testmodule Signal
--- TestEZ specification for the Signal module.
--- Run inside Roblox Studio with a TestEZ runner, or via `lune` with a Roblox mock.
---
--- To run in Studio:
---   1. Place this ModuleScript under a TestsRunner Script.
---   2. Require TestEZ and call `TestEZ.TestBootstrap:run({ script })`.

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Signal = require(ReplicatedStorage.Modules.Signal)

    describe("Signal.new", function()
        it("should return a signal object", function()
            local signal = Signal.new()
            expect(signal).to.be.ok()
        end)
    end)

    describe("Signal:connect", function()
        it("should call the callback when fired", function()
            local signal = Signal.new()
            local called = false
            signal:connect(function()
                called = true
            end)
            signal:fire()
            -- Give task.spawn a chance to execute.
            task.wait()
            expect(called).to.equal(true)
        end)

        it("should pass arguments to the callback", function()
            local signal = Signal.new()
            local received: number = 0
            signal:connect(function(value: number)
                received = value
            end)
            signal:fire(42)
            task.wait()
            expect(received).to.equal(42)
        end)

        it("should support multiple connections", function()
            local signal = Signal.new()
            local count = 0
            signal:connect(function()
                count += 1
            end)
            signal:connect(function()
                count += 1
            end)
            signal:fire()
            task.wait()
            expect(count).to.equal(2)
        end)
    end)

    describe("Connection:disconnect", function()
        it("should stop the callback from being called after disconnect", function()
            local signal = Signal.new()
            local count = 0
            local conn = signal:connect(function()
                count += 1
            end)
            signal:fire()
            task.wait()
            conn:disconnect()
            signal:fire()
            task.wait()
            expect(count).to.equal(1)
        end)

        it("should set connected to false", function()
            local signal = Signal.new()
            local conn = signal:connect(function() end)
            expect(conn.connected).to.equal(true)
            conn:disconnect()
            expect(conn.connected).to.equal(false)
        end)

        it("should be safe to call disconnect multiple times", function()
            local signal = Signal.new()
            local conn = signal:connect(function() end)
            conn:disconnect()
            expect(function()
                conn:disconnect()
            end).never.to.throw()
        end)
    end)

    describe("Signal:once", function()
        it("should only fire the callback once", function()
            local signal = Signal.new()
            local count = 0
            signal:once(function()
                count += 1
            end)
            signal:fire()
            signal:fire()
            task.wait()
            expect(count).to.equal(1)
        end)
    end)

    describe("Signal:disconnectAll", function()
        it("should remove all connections", function()
            local signal = Signal.new()
            local count = 0
            signal:connect(function()
                count += 1
            end)
            signal:connect(function()
                count += 1
            end)
            signal:disconnectAll()
            signal:fire()
            task.wait()
            expect(count).to.equal(0)
        end)
    end)

    describe("Signal:destroy", function()
        it("should disconnect all connections and be safe to call", function()
            local signal = Signal.new()
            local count = 0
            signal:connect(function()
                count += 1
            end)
            signal:destroy()
            signal:fire()
            task.wait()
            expect(count).to.equal(0)
        end)
    end)
end
