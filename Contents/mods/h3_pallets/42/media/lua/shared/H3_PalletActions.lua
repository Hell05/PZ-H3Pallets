---@diagnostic disable: undefined-global
-- ============================================================================
-- This file handles the action processing for the pallets
-- ============================================================================
-- Did you know?

-- Triatomic hydrogen or H3 is an unstable triatomic molecule containing only
-- three hydrogen atoms making it the simplest triatomic molecule.

-- Being unstable, the molecule breaks up in under a millionth of a second.
-- Its fleeting lifetime makes it rare, but it is quite commonly formed and 
-- destroyed in the universe thanks to the commonness of the trihydrogen cation.
-- The infrared spectrum of H3 due to vibration and rotation is very similar to
-- that of the ion, H+3. In the early universe this ability to emit infrared
-- light allowed the primordial hydrogen and helium gas to cool down so as to
-- form stars.
-- ============================================================================
-- Hey it's Hell, thanks for checking out the mod! I tried to make it readable

-- It's primarily built on the vanilla ISTakeBricks action which I've beefed up 
-- so it can handle bidirectional item transfers and sprite overlays. All the
-- tiles are made in Gimp from existing game assets and or rendered world items
-- from blender through an isometric camera view with a rotation of 60x 45z
-- ============================================================================

require "TimedActions/ISBaseTimedAction"
H3_InteractPallet = ISBaseTimedAction:derive("H3_InteractPallet")

--[[ returns an item table as such e.g. 
{                              |{
    ["Base.PropaneTank"] = {   |    ["Base.SteelIngot"] = {
        property = "delta",    |        property = "normal",
        properties = {         |        properties = {
            [0.5] = 2,         |            normal = 5,
            [0.8] = 1,         |        }
        }                      |    }
    }                          |}
}                              |
--]]

local function GetItemProperties(itemObj, itemTable)
    if not itemObj then return itemTable end

    itemTable = itemTable or {}

    local fullType = itemObj:getFullType()
    local itemData = itemTable[fullType]

    if not itemData then
        itemData = {
            property = nil,
            properties = {}
        }

        itemTable[fullType] = itemData
    end

    if instanceof(itemObj, "DrainableComboItem") then
        itemData.property = "delta"
        local itemDelta = itemObj:getCurrentUsesFloat()
        itemData.properties[itemDelta] = (itemData.properties[itemDelta] or 0) + 1

    elseif itemObj:hasComponent(ComponentType.Durability) then
        itemData.property = "condition"
        local condition = itemObj:getCondition()
        itemData.properties[condition] = (itemData.properties[condition] or 0) + 1

    else
        itemData.property = "normal"
        itemData.properties.normal = (itemData.properties.normal or 0) + 1
    end

    return itemTable
end

local function H3_PlayerRequiredItems(player, itemInput)
    if not player or not itemInput then
        return nil
    end

    -- if multiple items listed in itemType then generate a joint table
    if type(itemInput) == "table" then
        local resultTable = {}
        for _, item in ipairs(itemInput) do
            resultTable.append(H3_PlayerRequiredItems(player, item))
        end
        return resultTable
    end
    local itemType = itemInput

    -- check player inventory first
    local itemTable = {}
    local inventoryItems = player:getInventory():getAllTypeRecurse(itemType)
    for i = 0, inventoryItems:size() - 1 do
        local item = inventoryItems:get(i)
        itemTable = GetItemProperties(item, itemTable)
    end

    -- check ground in 3x3 around players current location
    local groundItems = buildUtil.getMaterialOnGround(player:getSquare())
    local ground = groundItems[itemType]

    if ground then
        for _, item in ipairs(ground) do
            itemTable = GetItemProperties(item, itemTable)
        end
    end
    print("ItemType: " .. tostring(itemType))
    if not itemTable[itemType] then
        print("table empty lets return default properties")
        itemTable = { [itemType] = { property = "normal", properties = { normal = 0 } } }
    end
    print("ItemTable: " .. tostring(itemTable))
    return itemTable
end

-- ============================================================================
-- Vanilla ISTakeBricks player handling
-- ============================================================================

function H3_InteractPallet:isValid()
    if not self.pallet:isExistInTheWorld() then
        return false
    end

    -- if amonnt > 0 we are adding items to pallet so check if player has them
    if self.amount > 0 then
        local availableItems = H3_PlayerRequiredItems(self.character, self.item)
        local value = self.propertyData.value
        if not availableItems then return end

        local specificPropertyCount = availableItems[self.item].properties[value]
        return self.amount <= specificPropertyCount
    end

    -- else we are taking from pallet, player inventory doesn't matter
    return true
end

function H3_InteractPallet:waitToStart()
    self.character:faceThisObject(self.pallet)
    return self.character:shouldBeTurning()
end

function H3_InteractPallet:update()
    self.character:faceThisObject(self.pallet)
	self.character:setMetabolicTarget(Metabolics.HeavyDomestic);
end

function H3_InteractPallet:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function H3_InteractPallet:stop()
    ISBaseTimedAction.stop(self);
end

function H3_InteractPallet:perform()
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self);
end

-- ============================================================================
-- Main logic
-- ============================================================================

local function GetRequiredItems(player, itemType, amount, value)
    local inventoryItems = {}
    local groundItems = {}

    if not player or not itemType or not amount or amount <= 0 then
        return inventoryItems, groundItems
    end

    local availableItems = H3_PlayerRequiredItems(player, itemType)

    if not availableItems then return end
    local specificPropertyCount = availableItems[itemType].properties[value]
    if amount > specificPropertyCount then return end

    -- check player inventory first, if enough then return items
    local found = 0
    local invItems = player:getInventory():getAllTypeRecurse(itemType)
    for i = 0, invItems:size() - 1 do
        local item = invItems:get(i)
        local itemTable = GetItemProperties(item, itemTable)
        if itemTable and itemTable[itemType].properties[value] then
            inventoryItems[#inventoryItems + 1] = item
            found = found + 1
        end
        if found >= amount then
            return inventoryItems, groundItems
        end
    end

    -- check ground in 3x3 grid for the remaining items
    local groundMap = buildUtil.getMaterialOnGround(player:getSquare())
    local grndItems = groundMap[itemType]
    if grndItems then
        for _, item in ipairs(grndItems) do
            local itemTable = GetItemProperties(item, itemTable)
            if itemTable and itemTable[itemType].properties[value] then
                groundItems[#groundItems + 1] = item
                found = found + 1
            end
            if found >= amount then
                break
            end
        end
    end

    return inventoryItems, groundItems
end

local function ConsumeRequiredItems(player, itemType, amount, value)
    if not player or not itemType or not amount then return false end

    -- check if the items are available and return them
    local inventoryItems, groundItems = GetRequiredItems(player, itemType, value, amount)
    if #inventoryItems + #groundItems < amount then return false end
    -- consume inventory first
    local remaining = amount
    if inventoryItems then
        for i = 1, #inventoryItems do
            local item = inventoryItems[i]
            local container = item:getContainer()
            if not container then return false end

            container:DoRemoveItem(item)
            sendRemoveItemFromContainer(container, item)

            if container == player:getInventory() then
                player:removeAttachedItem(item)

                if player:isEquipped(item) then
                    player:removeFromHands(item)
                    player:removeWornItem(item, false)
                    triggerEvent("OnClothingUpdated", player)
                end
            end
        end
        remaining = amount - #inventoryItems
    end

    -- consume remaining from groundItems
    if groundItems then
        for i = 1, remaining do
            local item = groundItems[i]
            local worldObj = item:getWorldItem()
            if not worldObj then return false end

            worldObj:getSquare():transmitRemoveItemFromSquare(worldObj)
        end
        remaining = amount - #groundItems
    end
    if remaining > 0 then
        return false
    end
    return true
end

local function CreateItems(player, itemType, amount, value)
    if not player or not itemType or not amount then
        return false
    end

    for _ = 1, amount do
        local itemObj = player:getInventory():AddItem(itemType)

        if itemObj:getConditionMax() > 0 then
        itemObj:setCondition(value or 0)

        elseif itemObj:IsDrainable() then
            itemObj:setUsedDelta(value or 0)
        end

        sendAddItemToContainer(player:getInventory(), itemObj)
    end
end

function H3_InteractPallet:complete()
    -- if amount is positive then add items to pallet, consume items from player
    if self.amount > 0 then
        if not ConsumeRequiredItems(self.character, self.item, self.amount, self.propertyData.value) then
            return false
        end

    -- elseif negative then remove items from pallet, add them to player inventory
    elseif self.amount < 0 then
        CreateItems(self.character, self.item, math.abs(self.amount), self.propertyData.value)
    end

    -- update sprite
    self.pallet:setSprite(self.sprite)
    self.pallet:transmitUpdatedSpriteToClients()

    local modData = self.pallet:getModData()
    local movableData = modData.movableData or {}
    modData.movableData = movableData

    -- update moveableData (this is what travels with the moveable Item when picked up)
    movableData.H3_itemCount = (movableData.H3_itemCount or 0) + self.amount
    movableData.H3_itemType = self.item

    if movableData.H3_itemCount == 0 then
        movableData.H3_itemType = nil
    end

    self.pallet:transmitModData()
    return true
end

function H3_InteractPallet:getDuration()
    if self.character:isTimedActionInstant() then
        return 1;
    end
    return 10 * math.abs(self.amount);
end

function H3_InteractPallet:new(character, pallet, square, sprite, item, amount, propertyData)
    local o = ISBaseTimedAction.new(self, character)
	o.character = character;
	o.pallet = pallet;
	o.square = square;
	o.sprite = sprite;
	o.item = item;
    o.amount = amount;
    o.propertyData = propertyData;
    o.maxTime = o:getDuration();
	o.stopOnWalk = true;
	o.stopOnRun = true;
	return o;
end