local Tinkr, Bastion = ...

-- Create a new ItemBook class
---@class ItemBook
local ItemBook = {}
ItemBook.__index = ItemBook

-- Constructor
---@return ItemBook
function ItemBook:New()
    local self = setmetatable({}, ItemBook)
    self.items = {}
    self.nameCache = {}  -- 添加名称缓存
    return self
end

-- Get a spell from the ItemBook
---@param id number
---@return Item
function ItemBook:GetItem(id)
    if self.items[id] == nil then
        self.items[id] = Bastion.Item:New(id)
    end

    return self.items[id]
end

-- 通过名称获取物品
---@param name string 物品名称或名称的一部分
---@return Item|nil 如果找到返回物品对象，否则返回nil
function ItemBook:GetItemByName(name)
    -- 先检查缓存
    if self.nameCache[name] then
        return self.items[self.nameCache[name]]
    end
    
    -- 搜索背包
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local itemID = GetContainerItemID(bag, slot)
            if itemID then
                local itemName = GetItemInfo(itemID)
                if itemName and itemName:lower():find(name:lower()) then
                    -- 缓存物品ID对应的名称查询
                    self.nameCache[name] = itemID
                    
                    -- 获取并返回物品对象
                    return self:GetItem(itemID)
                end
            end
        end
    end
    
    return nil
end

return ItemBook
