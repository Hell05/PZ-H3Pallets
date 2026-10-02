-- ============================================================================
-- This file handles the action processing for the pallets
-- ============================================================================
--  Did you know?

--  Triatomic hydrogen or H3 is an unstable triatomic molecule containing only
--  three hydrogen atoms. As a result it's the simplest triatomic molecule and
--  it's relatively simple to numerically solve the quantum mechanics 
--  description of the particles.

--  Being unstable, the molecule breaks up in under a millionth of a second.
--  Its fleeting lifetime makes it rare, but it is quite commonly formed and 
--  destroyed in the universe thanks to the commonness of the trihydrogen 
--  cation. The infrared spectrum of H3 due to vibration and rotation is very 
--  similar to that of the ion, H+3. In the early universe this ability to emit 
--  infrared light allowed the primordial hydrogen and helium gas to cool down
--  so as to form stars.

--  Hey this is Hell, thanks for checking out the mod! It's primarily built on the 
--  vanilla ISTakeBricks action which I've beefed up so it can handle bidirectional 
--  item transfers and sprite overlays. All the tiles are made in Gimp from existing
--  game assets and or rendered world items from blender through an isometric camera
--  view with a rotation of 60 degrees on the x axis and 45 degrees on the z axis.
-- ============================================================================

require "TimedActions/ISBaseTimedAction"
H3_InteractPallet = ISBaseTimedAction:derive("H3_InteractPallet")

-- check if item is normal or if it matches given useDelta
local function IsDrainableDelta(item, delta)
    if not item then
        return false
    end

    if not instanceof(item, "DrainableComboItem") then
        return true
    end

    return item:getCurrentUsesFloat() == delta
end

-- global so client side context UI can use it too
function H3_PlayerRequiredItems(player, itemType, delta)
    local count = 0

    if not player or not itemType then
        return count
    end

    -- check player inventory first
    local items = player:getInventory():getAllTypeRecurse(itemType)
    for i = 0, items:size() - 1 do
        local item = items:get(i)

        if IsDrainableDelta(item, delta) then
            count = count + 1
        end
    end

    -- check ground in 3x3 around players current location
    local groundItems = buildUtil.getMaterialOnGround(player:getSquare())
    local ground = groundItems[itemType]

    if ground then
        for _, item in ipairs(ground) do
            if IsDrainableDelta(item, delta) then
                count = count + 1
            end
        end
    end

    return count
end


-- ============================================================================
-- Vanilla ISTakeBricks player handling
-- ============================================================================

function H3_InteractPallet:isValid()
    if not self.pallet:isExistInTheWorld() then
        return false
    end

    if self.amount > 0 then
        return self.amount <= H3_PlayerRequiredItems(self.character, self.item, self.delta)
    end

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

local function GetRequiredItems(player, itemType, delta, amount)
    local inventoryItems = {}
    local groundItems = {}

    if not player or not itemType or not amount or amount <= 0 then
        return inventoryItems, groundItems
    end

    -- check player inventory first, if enough then return items
    local found = 0
    local items = player:getInventory():getAllTypeRecurse(itemType)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if IsDrainableDelta(item, delta) then
            inventoryItems[#inventoryItems + 1] = item
            found = found + 1

            if found >= amount then
                return inventoryItems, groundItems
            end
        end
    end

    -- check ground in 3x3 grid for the remaining items
    local groundMap = buildUtil.getMaterialOnGround(player:getSquare())
    local itemsOnGround = groundMap[itemType]
    if itemsOnGround then
        for _, item in ipairs(itemsOnGround) do
            if IsDrainableDelta(item, delta) then
                groundItems[#groundItems + 1] = item
                found = found + 1

                if found >= amount then
                    break
                end
            end
        end
    end

    return inventoryItems, groundItems
end

local function ConsumeRequiredItems(player, itemType, amount, delta)
    if not player or not itemType or not amount then return false end

    -- check if the items are available and return them
    local inventoryItems, groundItems = GetRequiredItems(player, itemType, delta, amount)
    if #inventoryItems + #groundItems < amount then return false end

    -- consume inventory first
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

    -- consume remaining from groundItems
    local remaining = amount - #inventoryItems
    for i = 1, remaining do
        local item = groundItems[i]
        local worldObj = item:getWorldItem()
        if not worldObj then return false end

        worldObj:getSquare():transmitRemoveItemFromSquare(worldObj)
    end

    return true
end

local function CreateItems(player, itemType, amount, delta)
    if not player or not itemType or not amount then
        return false
    end

    amount = math.abs(amount)
    for i = 1, amount do
        local item = player:getInventory():AddItem(itemType)

        if instanceof(item, "DrainableComboItem") then
            item:setUsedDelta(delta or 0)
        end

        sendAddItemToContainer(player:getInventory(), item)
    end
end

function H3_InteractPallet:complete()
    -- if amount is positive then add items to pallet, consume items from player
    if self.amount > 0 then
        if not ConsumeRequiredItems(self.character, self.item, self.amount, self.delta) then
            return false
        end

    -- elseif negative then remove items from pallet, add them to player inventory
    elseif self.amount < 0 then
        CreateItems(self.character, self.item, self.amount, self.delta)
    end

    -- update overlay
    self.pallet:setOverlaySprite(self.overlay)
    self.pallet:transmitUpdatedSpriteToClients()

    local modData = self.pallet:getModData()
    local movableData = modData.movableData or {}
    modData.movableData = movableData

    -- update moveableData (this is what travels with the moveable Item when picked up)
    movableData.H3_itemCount = (movableData.H3_itemCount or 0) + self.amount
    movableData.H3_itemType = self.item
    movableData.H3_itemDelta = self.delta
    movableData.H3_overlaySprite = self.overlay

    if movableData.H3_itemCount == 0 then
        movableData.H3_itemType = nil
        movableData.H3_overlaySprite = nil
        movableData.H3_itemDelta = nil
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

function H3_InteractPallet:new(character, pallet, square, overlaySprite, item, amount, delta)
    local o = ISBaseTimedAction.new(self, character)
	o.character = character;
	o.pallet = pallet;
	o.square = square;
	o.overlay = overlaySprite;
	o.item = item;
    o.amount = amount;
    o.delta = delta;
    o.maxTime = o:getDuration();
	o.stopOnWalk = true;
	o.stopOnRun = true;
	return o;
end