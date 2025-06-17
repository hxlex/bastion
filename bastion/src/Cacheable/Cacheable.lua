local Tinkr, Bastion = ...

-- Define a Cacheable class
---@class Cacheable
local Cacheable = {
    cache = nil,
    callback = nil,
    value = nil,
    -- __eq = function(self, other)
    --     return self.value.__eq(self.value, other)
    -- end
}

-- On index check the cache to be valid and return the value or reconstruct the value and return it
function Cacheable:__index(k)
    if Cacheable[k] then
        return Cacheable[k]
    end

    if self.cache == nil then
        error("Cacheable:__index: " .. k .. " does not exist")
    end

    if not self.cache:IsCached('self') then
        -- 直接同步更新，避免在__index中使用异步处理
        self.value = self.callback()
        self.cache:Set('self', self.value, 0.1)
    end

    return self.value[k]
end

-- When the object is accessed return the value
---@return string
function Cacheable:__tostring()
    return "Bastion.__Cacheable(" .. tostring(self.value) .. ")"
end

-- Create
---@param value any
---@param cb fun():any
function Cacheable:New(value, cb)
    local self = setmetatable({}, Cacheable)

    self.cache = Bastion.Cache:New()
    self.value = value
    self.callback = cb

    self.cache:Set('self', self.value, 0.1)

    return self
end

-- Try to update the value
---@return nil
function Cacheable:TryUpdate()
    if not self.cache:IsCached("value") then
        -- 使用异步处理更新值
        local self_local = self
        Scorpio.Continue(function()
            self_local.value = self_local.callback()
        end)
    end
end

-- Update the value
---@return nil
function Cacheable:Update()
    -- 使用异步处理更新值
    local self_local = self
    Scorpio.Continue(function()
        self_local.value = self_local.callback()
    end)
end

-- Set a new value
---@param value any
function Cacheable:Set(value)
    self.value = value
end

-- Set a new callback
---@param cb fun():any
function Cacheable:SetCallback(cb)
    self.callback = cb
end

return Cacheable
