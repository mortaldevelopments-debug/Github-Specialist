--!strict

--- @class Signal
--- A lightweight, strongly-typed custom Signal (event emitter) for decoupled communication.
--- Supports `connect`, `once`, `fire`, `wait`, and `disconnectAll`.
---
--- Usage:
--- ```lua
--- local onCoinChanged = Signal.new()
--- local conn = onCoinChanged:connect(function(amount) print(amount) end)
--- onCoinChanged:fire(50)
--- conn:disconnect()
--- ```

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

--- Represents a single subscription to a Signal.
export type Connection = {
    disconnect: (self: Connection) -> (),
    connected: boolean,
}

--- A typed signal that fires callbacks with arguments matching T...
export type SignalObject<T...> = {
    connect: (self: SignalObject<T...>, callback: (T...) -> ()) -> Connection,
    once: (self: SignalObject<T...>, callback: (T...) -> ()) -> Connection,
    fire: (self: SignalObject<T...>, T...) -> (),
    wait: (self: SignalObject<T...>) -> T...,
    disconnectAll: (self: SignalObject<T...>) -> (),
    destroy: (self: SignalObject<T...>) -> (),
}

local function newConnection(signal: any, callback: (...any) -> ()): Connection
    return setmetatable({
        _signal = signal,
        _callback = callback,
        connected = true,
    }, Connection) :: any
end

--- Disconnects this subscription so the callback is no longer invoked.
function Connection:disconnect()
    if not self.connected then
        return
    end
    self.connected = false
    local connections: { any } = self._signal._connections
    local index = table.find(connections, self)
    if index then
        table.remove(connections, index)
    end
end

--- Creates a new Signal instance.
--- @return SignalObject<T...>
function Signal.new<T...>(): SignalObject<T...>
    return setmetatable({
        _connections = {} :: { any },
    }, Signal) :: any
end

--- Subscribes `callback` to be invoked each time the signal fires.
--- @param callback (T...) -> () -- The function to call when fired.
--- @return Connection
function Signal:connect(callback: (...any) -> ()): Connection
    assert(type(callback) == "function", "callback must be a function")
    local conn = newConnection(self, callback)
    table.insert(self._connections, conn)
    return conn
end

--- Subscribes `callback` to fire only once, then automatically disconnects.
--- @param callback (T...) -> ()
--- @return Connection
function Signal:once(callback: (...any) -> ()): Connection
    local conn: Connection
    conn = self:connect(function(...)
        conn:disconnect()
        callback(...)
    end)
    return conn
end

--- Fires all connected callbacks with the given arguments.
--- Each callback runs in its own `task.spawn` so one error cannot block others.
--- @param ... T... -- Arguments forwarded to every callback.
function Signal:fire(...)
    -- Snapshot the connections array so a disconnect inside a callback is safe.
    local snapshot = table.clone(self._connections)
    for _, conn in snapshot do
        if conn.connected then
            task.spawn(conn._callback, ...)
        end
    end
end

--- Yields the calling coroutine until the signal fires and returns the arguments.
--- @return T...
function Signal:wait()
    local thread = coroutine.running()
    self:once(function(...)
        task.spawn(thread, ...)
    end)
    return coroutine.yield()
end

--- Disconnects all current subscriptions.
function Signal:disconnectAll()
    for _, conn in self._connections do
        conn.connected = false
    end
    self._connections = {}
end

--- Destroys the signal, disconnecting all subscriptions.
function Signal:destroy()
    self:disconnectAll()
end

return Signal
