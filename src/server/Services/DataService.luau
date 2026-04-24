--!strict

--- @class DataService
--- Wraps `DataStoreService` with automatic retry logic and structured error reporting.
--- All public methods are safe to call from within `PlayerRemoving` handlers.
---
--- 🟡 Warning: DataStore calls are rate-limited by Roblox.
---             Callers should use `task.defer` / `task.spawn` to avoid blocking game logic.

local DataStoreService = game:GetService("DataStoreService")

local MAX_RETRIES = 3
local RETRY_DELAY = 2 -- seconds between retries

local DataService = {}
DataService.__index = DataService

export type DataServiceObject = {
    get: (self: DataServiceObject, store: string, key: string) -> (any?, string?),
    set: (self: DataServiceObject, store: string, key: string, value: any) -> (boolean, string?),
    update: (
        self: DataServiceObject,
        store: string,
        key: string,
        transform: (old: any?) -> any
    ) -> (boolean, string?),
    destroy: (self: DataServiceObject) -> (),
}

--- Creates a new DataService instance.
--- @return DataServiceObject
function DataService.new(): DataServiceObject
    return setmetatable({
        _stores = {} :: { [string]: DataStore },
    }, DataService) :: any
end

--- @private
--- Lazily retrieves or creates a named DataStore handle.
--- @param storeName string
--- @return DataStore
function DataService:_getStore(storeName: string): DataStore
    if not self._stores[storeName] then
        self._stores[storeName] = DataStoreService:GetDataStore(storeName)
    end
    return self._stores[storeName]
end

--- @private
--- Generic retry wrapper for a single DataStore operation.
--- @param label string -- Human-readable label for warning output.
--- @param fn () -> any -- The DataStore call to attempt.
--- @return boolean, any -- success flag and result/error.
function DataService:_withRetry(label: string, fn: () -> any): (boolean, any)
    for attempt = 1, MAX_RETRIES do
        local ok, result = pcall(fn)
        if ok then
            return true, result
        end
        warn(`[DataService] {label} failed (attempt {attempt}/{MAX_RETRIES}): {result}`)
        if attempt < MAX_RETRIES then
            task.wait(RETRY_DELAY)
        end
    end
    return false, `{label} failed after {MAX_RETRIES} attempts`
end

--- Retrieves a value from a DataStore with automatic retry.
--- @param store string -- DataStore name.
--- @param key string -- Entry key.
--- @return any?, string? -- The stored value (or `nil`) and an optional error string.
function DataService:get(store: string, key: string): (any?, string?)
    assert(type(store) == "string" and #store > 0, "store must be a non-empty string")
    assert(type(key) == "string" and #key > 0, "key must be a non-empty string")

    local dataStore = self:_getStore(store)
    local ok, result = self:_withRetry(`GetAsync({store}/{key})`, function()
        return dataStore:GetAsync(key)
    end)

    if ok then
        return result, nil
    end
    return nil, result
end

--- Writes a value to a DataStore with automatic retry.
--- @param store string -- DataStore name.
--- @param key string -- Entry key.
--- @param value any -- Value to persist. Must not be `nil`.
--- @return boolean, string? -- `true` on success, or `false` plus an error string.
function DataService:set(store: string, key: string, value: any): (boolean, string?)
    assert(type(store) == "string" and #store > 0, "store must be a non-empty string")
    assert(type(key) == "string" and #key > 0, "key must be a non-empty string")
    assert(value ~= nil, "value cannot be nil; use :remove() to delete a key")

    local dataStore = self:_getStore(store)
    local ok, err = self:_withRetry(`SetAsync({store}/{key})`, function()
        dataStore:SetAsync(key, value)
    end)

    return ok, if not ok then err else nil
end

--- Atomically updates a value using `UpdateAsync` with retry logic.
--- @param store string -- DataStore name.
--- @param key string -- Entry key.
--- @param transform (old: any?) -> any -- Pure function; receives the current value, returns the new one.
--- @return boolean, string?
function DataService:update(
    store: string,
    key: string,
    transform: (old: any?) -> any
): (boolean, string?)
    assert(type(store) == "string" and #store > 0, "store must be a non-empty string")
    assert(type(key) == "string" and #key > 0, "key must be a non-empty string")
    assert(type(transform) == "function", "transform must be a function")

    local dataStore = self:_getStore(store)
    local ok, err = self:_withRetry(`UpdateAsync({store}/{key})`, function()
        dataStore:UpdateAsync(key, transform)
    end)

    return ok, if not ok then err else nil
end

--- Destroys the DataService, releasing all DataStore references.
function DataService:destroy()
    self._stores = {}
end

return DataService
