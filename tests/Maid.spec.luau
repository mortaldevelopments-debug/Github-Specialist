--!strict

--- @testmodule Maid
--- TestEZ specification for the Maid module.
--- Run inside Roblox Studio with a TestEZ runner.

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Maid = require(ReplicatedStorage.Modules.Maid)

    describe("Maid.new", function()
        it("should return a maid object", function()
            local maid = Maid.new()
            expect(maid).to.be.ok()
        end)
    end)

    describe("Maid:giveTask", function()
        it("should accept a function task", function()
            local maid = Maid.new()
            expect(function()
                maid:giveTask(function() end)
            end).never.to.throw()
        end)

        it("should reject nil tasks", function()
            local maid = Maid.new()
            expect(function()
                maid:giveTask(nil :: any)
            end).to.throw()
        end)
    end)

    describe("Maid:give", function()
        it("should return the same value that was passed", function()
            local maid = Maid.new()
            local fn = function() end
            local returned = maid:give(fn)
            expect(returned).to.equal(fn)
        end)
    end)

    describe("Maid:cleanAll", function()
        it("should call function tasks on cleanAll", function()
            local maid = Maid.new()
            local called = false
            maid:giveTask(function()
                called = true
            end)
            maid:cleanAll()
            expect(called).to.equal(true)
        end)

        it("should disconnect RBXScriptConnections on cleanAll", function()
            local maid = Maid.new()
            local bindable = Instance.new("BindableEvent")
            local fired = false
            local conn = bindable.Event:Connect(function()
                fired = true
            end)
            maid:giveTask(conn)
            maid:cleanAll()
            bindable:Fire()
            task.wait()
            -- Connection was disconnected, so fired should still be false.
            expect(fired).to.equal(false)
            bindable:Destroy()
        end)

        it("should destroy Instance tasks on cleanAll", function()
            local maid = Maid.new()
            local part = Instance.new("Part")
            maid:giveTask(part)
            maid:cleanAll()
            expect(part.Parent).to.equal(nil)
        end)

        it("should call :destroy() on table tasks that implement it", function()
            local maid = Maid.new()
            local destroyed = false
            local obj = {
                destroy = function(_self)
                    destroyed = true
                end,
            }
            maid:giveTask(obj :: any)
            maid:cleanAll()
            expect(destroyed).to.equal(true)
        end)

        it("should clean tasks in LIFO order", function()
            local maid = Maid.new()
            local order: { number } = {}
            maid:giveTask(function()
                table.insert(order, 1)
            end)
            maid:giveTask(function()
                table.insert(order, 2)
            end)
            maid:giveTask(function()
                table.insert(order, 3)
            end)
            maid:cleanAll()
            expect(order[1]).to.equal(3)
            expect(order[2]).to.equal(2)
            expect(order[3]).to.equal(1)
        end)

        it("should empty the task list after cleanAll", function()
            local maid = Maid.new()
            local count = 0
            maid:giveTask(function()
                count += 1
            end)
            maid:cleanAll()
            maid:cleanAll() -- second call should do nothing
            expect(count).to.equal(1)
        end)
    end)

    describe("Maid:destroy", function()
        it("should clean all tasks on destroy", function()
            local maid = Maid.new()
            local called = false
            maid:giveTask(function()
                called = true
            end)
            maid:destroy()
            expect(called).to.equal(true)
        end)
    end)
end
