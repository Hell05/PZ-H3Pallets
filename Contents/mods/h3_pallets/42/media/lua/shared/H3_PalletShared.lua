---@diagnostic disable: undefined-global
-- ============================================================================
-- This file handles the action processing for the pallets [Version 3]
-- ============================================================================
-- Did you know?

-- Triatomic hydrogen or H3 is an unstable triatomic molecule containing only
-- three hydrogen atoms making it the simplest triatomic molecule.

-- Being unstable, the molecule breaks up in under a millionth of a second.
-- It's fleeting lifetime makes it rare, but it is quite commonly formed and 
-- destroyed in the universe due to the commonness of the trihydrogen cation.
-- The infrared spectrum of H3 due to vibration and rotation is very similar
-- to that of the ion H+3. In the early universe this ability to emit infrared
-- light allowed the primordial hydrogen and helium gas to cool down so as to
-- form stars.
-- ============================================================================
-- Hey it's Hell, thanks for checking out the mod!

-- Its primarily built on the vanilla ISTakeBricks action which I've beefed up
-- so it can handle bidirectional item transfers and moveablity. All the tiles
-- are made in Gimp from existing game assets and or rendered world items from
-- blender through an isometric camera view with a rotation setting of 60x 45z
-- ============================================================================

local sharedDebug = false  -- for testing only     disables :complete() from performing final changes.

require "TimedActions/ISBaseTimedAction"
H3_InteractPallet = ISBaseTimedAction:derive("H3_InteractPallet")
local debugH3 = require("H3_GlobalUtils")

local import = require("H3_DefineItemTables")
local itemLookup = import and import.items
-- ============================================================================
-- Validation helper functions
-- ============================================================================

local function GetPalletModData(modData, pname)
    local movableData = modData and modData.movableData
    if not movableData then return end

    local fullTypes = movableData.H3_itemFullTypes or {}
    local total = movableData.H3_itemTotal or 0
    local fallback = {}
    for key, _ in pairs(fullTypes) do
        fallback = { [key] = { normal = total, }, }
        break
    end

    return {
        fullTypes = fullTypes,
        total = total,
        pname = movableData.H3_itemProperty or pname,
        ptable = movableData.H3_itemPropertyData or fallback
    }
end

local function PlayerHasAvailableItems(itemType, value, amount, inventoryItems, groundItems)
    if not inventoryItems and not groundItems then
        debugH3.warn("No inventory or ground items found. isValid() fail")
        return false
    end
    inventoryItems = inventoryItems or {}
    groundItems = groundItems or {}

    local availableItems = H3_GetAvailableItems(itemType, inventoryItems, groundItems)
    local specificPropertyCount = availableItems[itemType] and availableItems[itemType].ptable[value] or 0
    debugH3.log("Item: " .. tostring(itemType) .. " |  Property: " .. tostring(availableItems[itemType].pname) .. " | Value: " .. tostring(value) .. " | Count: " .. tostring(specificPropertyCount))

    if amount > specificPropertyCount then
        debugH3.warn("Player no longer has access to enough available items. Available: " .. tostring(specificPropertyCount) .. "  Required: " .. tostring(amount), "  isValid() fail")
        return false
    end
    return true
end

local function PalletHasAvailableItems(movableData, itemType, value, removeAmount)
    local available = movableData.ptable[itemType][value]
    debugH3.log("Item: " .. tostring(itemType) .. " |  Property: " .. tostring(movableData.pname) .. " | Total: " .. tostring(movableData.total) .. " | Value: " .. tostring(value) .. " | Available: " .. tostring(available))

    if removeAmount > movableData.total or removeAmount > available then
        debugH3.warn("removeAmount exceeds the pallet's stored item amount. PalletHasAvailableItems() fail")
        return false
    end

    return true
end

-- validates if pallet exists, if it has items and if player has access to required items
function H3_InteractPallet:isValid()
    debugH3.log("Client | RUN: isValid()")

    if self.error then
        debugH3.warn(self.error, " isValid() fail")
        return false
    end

    if not self.pallet:isExistInTheWorld() then
        debugH3.warn("Pallet doesn't exist in world. isValid() fail")
        return false
    end

    return true
end

-- ============================================================================
-- Vanilla ISTakeBricks timedAction handling
-- ============================================================================

function H3_InteractPallet:waitToStart()
    self.player:faceThisObject(self.pallet)
    return self.player:shouldBeTurning()
end

function H3_InteractPallet:update()
    self.player:faceThisObject(self.pallet)
	self.player:setMetabolicTarget(Metabolics.HeavyDomestic)
end

function H3_InteractPallet:start()
    self:setActionAnim("Loot")
    self.player:SetVariable("LootPosition", "Low")
end

function H3_InteractPallet:stop()
    ISBaseTimedAction.stop(self)
end

function H3_InteractPallet:perform()
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
end

-- ============================================================================
-- Inventory and pallet update logic
-- ============================================================================

local function GetResultSprite(itemName, total)
    for _, data in ipairs(itemLookup) do
        for _, itemType in ipairs(data.items) do
            if itemType == itemName then
                for _, stage in ipairs(data.stages) do
                    if total == stage.amount then
                        return stage.resultSprite
                    end
                end
            end
        end
    end
end

-- updates the modData for the pallet ready to be transmitted
local function UpdateModData(movableData, itemType, pname, value, amount)
    local updateData = {
        H3_itemFullTypes = nil,
        H3_itemTotal = 0,
        H3_itemProperty = "normal",
        H3_itemPropertyData = {},
    }

    -- if total is 0 we can just return default values to clear modData
    updateData.H3_itemTotal = movableData.total + amount
    if updateData.H3_itemTotal ~= 0 then

        updateData.H3_itemFullTypes = movableData.fullTypes or {}
        -- create an entry in fullTypes if there is none
        local exists = false
        for _, existingType in ipairs(updateData.H3_itemFullTypes) do
            if existingType == itemType then
                exists = true
                break
            end
        end

        if not exists then
            table.insert(updateData.H3_itemFullTypes, itemType)
        end

        local itemData = movableData.ptable[itemType] or {}
        local existingCount = itemData[value] or 0
        local sum = existingCount + amount
        updateData.H3_itemProperty = pname or "normal"

        -- if the sum is 0 we can clear the entry with nil
        if sum == 0 then
            itemData[value] = nil
        else
            itemData[value] = sum
        end

        updateData.H3_itemPropertyData = movableData.ptable
        updateData.H3_itemPropertyData[itemType] = itemData
    end

    return updateData
end

-- returns filtered inventoryItems and groundItems tables with itemObjects
local function GetRequiredItems(itemType, pname, value, amount, allInventoryItems, allGroundItems)

    local found = 0
    local resultInvItems = {}
    local resultGrndItems = {}

    -- get from player inventory first, if enough then return items
    local inventoryItems = allInventoryItems:getAllTypeRecurse(itemType)
    for i = 0, inventoryItems:size() - 1 do
        local itemObj = inventoryItems:get(i)

        if pname == "normal" then
            resultInvItems[#resultInvItems + 1] = itemObj
            found = found + 1

        elseif pname == "delta" then
            local itemDelta = math.floor(itemObj:getCurrentUsesFloat() * 100 + 0.5) / 100
            if itemDelta == value then
                resultInvItems[#resultInvItems + 1] = itemObj
                found = found + 1
            end

        elseif pname ==  "condition" then
            if itemObj:getCondition() == value then
                resultInvItems[#resultInvItems + 1] = itemObj
                found = found + 1
            end
        end

        if found >= amount then
            return resultInvItems, resultGrndItems
        end
    end

    -- check ground in 3x3 grid for the remaining items
    local groundItems = allGroundItems[itemType]
    if groundItems then
        for _, itemObj in ipairs(groundItems) do

            if pname == "normal" then
                resultGrndItems[#resultGrndItems + 1] = itemObj
                found = found + 1

            elseif pname == "delta" then
                if math.floor(itemObj:getCurrentUsesFloat() * 100 + 0.5) / 100 == value then
                    resultGrndItems[#resultGrndItems + 1] = itemObj
                    found = found + 1
                end

            elseif pname ==  "condition" then
                if itemObj:getCondition() == value then
                    resultGrndItems[#resultGrndItems + 1] = itemObj
                    found = found + 1
                end
            end

            if found >= amount then
                break
            end
        end
    end

    return resultInvItems, resultGrndItems
end

-- performs the item removal from player and vicinity
local function ConsumeItems(player, amount, inventoryItems, groundItems)

    if #inventoryItems + #groundItems < amount then
        debugH3.warn("Player no longer has access to enough available items.  ConsumeItems() fail")
        return false
    end

    -- consume inventory first
    local remaining = amount
    for i = 1, #inventoryItems do
        local item = inventoryItems[i]
        local container = item:getContainer()
        if not container then
            debugH3.warn("Container for item: ", item, "  not found.  ConsumeItems() fail")
            return false
        end

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

    -- consume remaining from groundItems
    for i = 1, remaining do
        local item = groundItems[i]
        local worldObj = item:getWorldItem()
        if not worldObj then
            debugH3.warn("WorldObject for item: ", item, "  not found.  ConsumeItems() fail")
            return false
        end

        worldObj:getSquare():transmitRemoveItemFromSquare(worldObj)
    end
    remaining = remaining - #groundItems

    if remaining > 0 then
        debugH3.warn("ConsumeItems() couldn't remove enough items from player. This is a bug, report it! Continuing safely to prevent item loss.")
        return false
    end
    return true
end

-- adds items to player inventory
local function CreateItems(player, itemType, pname, value, amount)
    for _ = 1, amount do
        local itemObj = player:getInventory():AddItem(itemType)

        if pname == "delta" then
            itemObj:setUsedDelta(value or 0)

        elseif pname == "condition" then
            itemObj:setCondition(value or 0)
        end

        sendAddItemToContainer(player:getInventory(), itemObj)
    end

    return true
end

function H3_InteractPallet:complete()
    debugH3.log("Server | RUN: complete()")

-- ============================================================================
-- moved code from :isValid() for data validation on server side

    debugH3.log("Server | Validating data...")
    -- collect movableModData
    self.movableData = GetPalletModData(self.pallet:getModData(), self.pname) or self.palletData

    if not self.movableData then
        debugH3.warn("Missing / failed to construct movableData isValid() fail")
        return false
    end
    debugH3.log("Pallet movableData  | Items: " .. tostring(self.movableData.fullTypes))
    debugH3.log("Total:" .. tostring(self.movableData.total) .. " | pname: " .. tostring(self.movableData.pname) .. " | ptable: " .. tostring(self.movableData.ptable))

    -- if amount > 0 we are adding items to pallet so check if player has them
    local allInventoryItems = self.player:getInventory()
    local allGroundItems = buildUtil.getMaterialOnGround(self.player:getSquare())

    if self.amount > 0 then
        if not PlayerHasAvailableItems(self.item, self.value, self.amount, allInventoryItems, allGroundItems) then
            return false
        end

    -- otherwise we are removing items from pallet, check if pallet has required contents
    elseif self.amount < 0 then
        local removeAmount = math.abs(self.amount)
        if not PalletHasAvailableItems(self.movableData, self.item, self.value, removeAmount) then
            return false
        end
    end

-- ============================================================================

    if sharedDebug then
        debugH3.log("Debug enabled, no server changes will be made. Exiting.")
        return false
    end
    -- if amount is positive then add items to pallet, consume items from player
    if self.amount > 0 then

        local inventoryItems, groundItems = GetRequiredItems(self.item, self.pname, self.value, self.amount, allInventoryItems, allGroundItems)
        if not ConsumeItems(self.player, self.amount, inventoryItems, groundItems) then
            return false
        end


    -- elseif negative then remove items from pallet, add them to player inventory
    elseif self.amount < 0 then
        local removeAmount = math.abs(self.amount)
        if not PalletHasAvailableItems(self.movableData, self.item, self.value, removeAmount)
            or not CreateItems(self.player, self.item, self.pname, self.value, removeAmount) then
                return false
        end
    end

    -- update and transmit modData
    local movableData = UpdateModData(self.movableData, self.item, self.pname, self.value, self.amount)
    local modData = self.pallet:getModData()
    modData.movableData = movableData
    self.pallet:transmitModData()
    debugH3.log("Pallet ModData successfully updated. | New Items: " .. tostring(modData.movableData.H3_itemFullTypes))
    debugH3.log("New Data: | H3_itemTotal:" .. tostring(modData.movableData.H3_itemTotal) .. " |  H3_itemProperty: " .. tostring(modData.movableData.H3_itemProperty) .. " | H3_itemPropertyData: " .. tostring(modData.movableData.H3_itemPropertyData))

    -- update and transmit sprite
    if movableData.H3_itemTotal > 0 then
        self.resultSprite = GetResultSprite(self.item, movableData.H3_itemTotal) or self.resultSprite
    end
    self.pallet:setSprite(getSprite(self.resultSprite))
    self.pallet:transmitUpdatedSpriteToClients()


    debugH3.log("Inventory and pallet updates finished: ... Success!")
    return true
end

function H3_InteractPallet:getDuration()
    if self.player:isTimedActionInstant() then
        return 1;
    end
    return 45 + math.abs(self.amount or 5)
end

function H3_InteractPallet:new(player, pallet, square, resultSprite, item, pname, value, amount, palletData)
    debugH3.log("Server | RUN: new()")
    local o = ISBaseTimedAction.new(self, player)
    o.error = nil

    -- from client :sendRequest()
	o.player = player
	o.pallet = pallet
	o.square = square
	o.resultSprite = resultSprite
	o.item = item
    o.pname = pname  -- stores normal, delta or condition
    o.value = value  -- stores the value of pname
    o.amount = amount  -- can be positive or negative
    o.palletData = palletData  -- stores movable modData regarding the pallet contents

    -- from :isValid()
    o.movableData = "verified"  -- read from worldObj or from palletData

    if not o.player or not o.pallet or not o.square or not o.resultSprite then
        o.error = "Missing  player / pallet / square / resultSprite  information."
    end
    if not o.item or not o.amount or not o.value or not o.palletData then
        o.error = "Missing  item / amount / value / client modData  information."
    end
    -- for timedActions
    o.maxTime = o:getDuration()
	o.stopOnWalk = true
	o.stopOnRun = true
	return o
end