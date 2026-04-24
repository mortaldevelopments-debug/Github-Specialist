--!strict

--- @class Maid
--- A utility class for managing cleanup of connections, instances, and functions.
--- Prevents memory leaks by tracking and destroying resources when a system shuts down.
---
--- Usage:
--- ```lua
--- local maid = Maid.new()
--- maid:giveTask(someSignal:Connect(handler))
--- maid:giveTask(someInstance)
--- -- later:
--- maid:cleanAll()
--- ```

local Maid = {}
Maid.__index = Maid

--- Any value that can be cleaned up by a Maid.
export type MaidTask =
    Instance
    | RBXScriptConnection
    | (() -> ())
    | { destroy: (self: any) -> () }
    | { Destroy: (self: any) -> () }

export type MaidObject = {
    give: <T>(self: MaidObject, task: T) -> T,
    giveTask: (self: MaidObject, task: MaidTask) -> (),
    cleanAll: (self: MaidObject) -> (),
    destroy: (self: MaidObject) -> (),
}

--- Creates a new Maid instance.
--- @return MaidObject
function Maid.new(): MaidObject
    return setmetatable({
        _tasks = {} :: { MaidTask },
    }, Maid) :: any
end

--- Adds a task and returns it, allowing inline usage.
--- @param task T -- The resource to track.
--- @return T
function Maid:give<T>(task: T): T
    self:giveTask(task :: any)
    return task
end

--- Adds a task to be cleaned up when `cleanAll` or `destroy` is called.
--- @param task MaidTask -- The resource to track.
function Maid:giveTask(task: MaidTask)
    assert(task ~= nil, "Task cannot be nil")
    table.insert(self._tasks, task)
end

--- Cleans up all tracked tasks in LIFO order and resets the task list.
function Maid:cleanAll()
    local tasks = self._tasks
    self._tasks = {}
    -- Clean in reverse order so later-added resources are freed first.
    for i = #tasks, 1, -1 do
        local task_ = tasks[i]
        if type(task_) == "function" then
            task_()
        elseif typeof(task_) == "RBXScriptConnection" then
            task_:Disconnect()
        elseif typeof(task_) == "Instance" then
            task_:Destroy()
        elseif type(task_) == "table" then
            if type((task_ :: any).destroy) == "function" then
                ;(task_ :: any):destroy()
            elseif type((task_ :: any).Destroy) == "function" then
                ;(task_ :: any):Destroy()
            end
        end
    end
end

--- Destroys the Maid, cleaning up all tracked tasks.
function Maid:destroy()
    self:cleanAll()
end

return Maid
