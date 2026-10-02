--[[
require "TimedActions/ISBaseTimedAction"

BSMP_InteractPallet = ISBaseTimedAction:derive("BSMP_InteractPallet")

local function isDrainableDelta(item, delta)
    if not item then
        return false
    end

    if not instanceof(item, "DrainableComboItem") then
        return true
    end

    return item:getCurrentUsesFloat() == delta
end

function BSMP_playerRequiredItems(player, itemType, delta)
    local count = 0

    if not player or not itemType then
        return count
    end

    local items = player:getInventory():getAllTypeRecurse(itemType)

    for i = 0, items:size() - 1 do
        local item = items:get(i)

        if isDrainableDelta(item, delta) then
            count = count + 1
        end
    end

    local groundItems = buildUtil.getMaterialOnGround(player:getSquare())
    local ground = groundItems[itemType]

    if ground then
        for _, item in ipairs(ground) do
            if isDrainableDelta(item, delta) then
                count = count + 1
            end
        end
    end

    return count
end

local function getRequiredItems(player, itemType, delta, amount)
    local inventoryItems = {}
    local groundItems = {}

    if not player or not itemType or not amount or amount <= 0 then
        return inventoryItems, groundItems
    end

    local found = 0
    local items = player:getInventory():getAllTypeRecurse(itemType)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isDrainableDelta(item, delta) then
            inventoryItems[#inventoryItems + 1] = item
            found = found + 1

            if found >= amount then
                return inventoryItems, groundItems
            end
        end
    end

    local groundMap = buildUtil.getMaterialOnGround(player:getSquare())
    local itemsOnGround = groundMap[itemType]
    if itemsOnGround then
        for _, item in ipairs(itemsOnGround) do
            if isDrainableDelta(item, delta) then
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

local function consumeRequiredItems(player, itemType, amount, delta)
    if not player or not itemType or not amount then return false end

    -- check if the items are available and return them
    local inventoryItems, groundItems = getRequiredItems(player, itemType, delta, amount)
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

local function createItems(player, itemType, amount, delta)
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

function BSMP_InteractPallet:isValid()
    if not self.pallet:isExistInTheWorld() then
        return false
    end

    if self.amount > 0 then
        return self.amount <= BSMP_playerRequiredItems(self.character, self.item, self.delta)
    end

    return true
end

function BSMP_InteractPallet:waitToStart()
    self.character:faceThisObject(self.pallet)
    return self.character:shouldBeTurning()
end

function BSMP_InteractPallet:update()
    self.character:faceThisObject(self.pallet)
	self.character:setMetabolicTarget(Metabolics.HeavyDomestic);
end

function BSMP_InteractPallet:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function BSMP_InteractPallet:stop()
    ISBaseTimedAction.stop(self);
end

function BSMP_InteractPallet:perform()
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self);
end

function BSMP_InteractPallet:complete()
    -- if amount is positive then add items to pallet, take items from player
    if self.amount > 0 then
        if not consumeRequiredItems(self.character, self.item, self.amount, self.delta) then
            return false
        end
    -- else if negative then remove items from pallet, give to player
    elseif self.amount < 0 then
        createItems(self.character, self.item, self.amount, self.delta)
    end

    -- in case the pallet has inventory then dump it on ground
    if self.pallet:getContainer() and not self.pallet:getContainer():isEmpty() then
        local items = self.pallet:dumpContentsInSquare();
    end
    self.pallet:getSquare():transmitRemoveItemFromSquare(self.pallet)

    -- create new IsoObject and entity to replace the old one if a sprite was provided
    if self.sprite then
	    local newPallet = IsoObject.new(getCell(), self.square, self.sprite);

        local info = SpriteConfigManager.getObjectInfoFromSprite(self.sprite);

        if info and info:getScript() and info:getScript():getParent() then
            local gameEntityScript = info:getScript():getParent();
            GameEntityFactory.CreateIsoObjectEntity(newPallet, gameEntityScript, true);
        end

	    self.square:AddTileObject(newPallet);
        newPallet:transmitCompleteItemToClients()
	    self.square:RecalcProperties();
    end

    return true;
end

function BSMP_InteractPallet:getDuration()
    if self.character:isTimedActionInstant() then
        return 1;
    end
    return 10 * math.abs(self.amount);
end

function BSMP_InteractPallet:new(character, pallet, square, sprite, item, amount, delta)
    local o = ISBaseTimedAction.new(self, character)
	o.character = character;
	o.pallet = pallet;
	o.square = square;
	o.sprite = sprite;
	o.item = item;
    o.amount = amount;
    o.delta = delta;
    o.maxTime = o:getDuration();
	o.stopOnWalk = true;
	o.stopOnRun = true;
	return o;
end
--]]