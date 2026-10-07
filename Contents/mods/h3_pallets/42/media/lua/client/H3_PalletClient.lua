---@diagnostic disable: undefined-global
-- ============================================================================
-- This file handles the client side context menu UI options [Version 4]
-- ============================================================================
-- Hey, this is Hell. A little context for this mod and its design process for
-- those that are interested (I assume you might be since you opened this file)
-- I tried to make the files as readable as possible since it helps me as much
-- as anyone else (my memory sucks ass) so I hope you find it helpful!

-- I decided to use the empty vanilla (brick) pallet as the base pallet for
-- everything including the sprites designed in gimp so they transition nicely.
-- The gold pallet sadly has a different empty pallet sprite when you take the
-- ingots from it but this is less noticeable since the gold covers most of
-- the sprite thankfully. I also added a recipe to craft the vanilla gold pallet
-- in case people want to have it for whatever reason. The normal pallet
-- stacking will not convert it back to the vanilla sprite, it gets converted.

-- Originally this file had a different pallet context menu entry coming from
-- entities. This is how vanilla does things with the ISTakeBricks logic, the
-- ContextMenuConfig specifies a customFunction = ContextMenuCode.TakeBricks
-- that called ISTakeBricks which you can see me reusing in PalletActions.lua

-- I decided after writing 18 entities for each ingot pallet this was not
-- the way I wanted to handle it, tried using overlay sprites and a single
-- source entity which was the empty pallet. This worked *okay* but when the
-- pallet got picked up it lost the overlaySprite so this was bad.

-- Now its all done through the right click context menu so its much cleaner!
-- ============================================================================

local clientDebug = false  -- for testing only     disables :sendRequest() from actually communicating with H3_PalletShared.lua

local debugH3 = require("H3_GlobalUtils")
local import = require("H3_DefineItemTables")

local itemLookup = import and import.items
local keys = import and import.keys
local vanillaPalletTable = import and import.vanillaPalletTable

if not itemLookup or not keys or not vanillaPalletTable then
    debugH3.error("Import(s) missing! [H3_PalletClient.lua] is returning safely.")
    return
end

local H3_Pallet = {}
H3_Pallet.__index = H3_Pallet

-- ============================================================================
-- UI Context Menu constructor helpers
-- ============================================================================

-- itemOption creator
local function UI_CreateItemOption(self, subMenu, data, stage, mode, amount, actionName, propertyData)
    -- construct the translation friendly context menu option text
    local textKey = "ContextMenu_" .. actionName
    debugH3.log(textKey, amount, propertyData.type)
    local displayText = getText(textKey, amount, getItemNameFromFullType(propertyData.type))

    if propertyData.pname == "delta" then
        textKey = textKey .. "_Delta"
        local value = string.format("%.0f", (propertyData.value * 100))
        displayText = getText(textKey, amount, value, getItemNameFromFullType(propertyData.type))

    elseif propertyData.pname == "condition" then
        textKey = textKey .. "_Condition"
        local value = string.format("%.0f", propertyData.value )
        displayText = getText(textKey, amount, value, getItemNameFromFullType(propertyData.type))
    end

    -- attach mechanics text
    if data.mechanics then
        for i = 1, 3 do
            if propertyData.type:find(tostring(i), 1, true) then
                local mechanicsItemText = "IGUI_VehicleType_" .. tostring(i)
                displayText = displayText .. " (" .. tostring(getText(mechanicsItemText)) .. ")"
                break
            end
        end
    end

    -- create the clickable option with callback to sendRequest
    local itemOption = subMenu:addOption(
        displayText,
        self,
        self.sendRequest,
        stage.resultSprite,
        amount,
        propertyData,
        mode
        )
    itemOption.iconTexture = getTexture(data.icon)

    if propertyData.count then
        if amount > propertyData.count then
            itemOption.notAvailable = true
        end
    end

    return itemOption
end

-- PalletMenu -> Add/Remove subMenu creator
local function UI_GetOrCreateSubMenu(parentMenu, subMenus, menuName, iconPath)
    if not parentMenu then return end

    local subMenu = subMenus[menuName]
    if not subMenu then
        local textKey = "ContextMenu_" .. menuName
        local displayText = getText(textKey)

        local option = parentMenu:addOption(displayText)
        if iconPath then
            option.iconTexture = getTexture(iconPath)
        end

        subMenu = ISContextMenu:getNew(parentMenu)
        parentMenu:addSubMenu(option, subMenu)

        subMenus[menuName] = subMenu
    end

    return subMenu
end

-- returns the stage based on mode and palletItemCount
local function GetStage(mode, data, palletItemCount)
    if mode == "Current" then
        for _, stage in ipairs(data.stages) do
            if stage.amount == palletItemCount then
                return stage
            end
        end

    elseif mode == "Next" then
        for _, stage in ipairs(data.stages) do
            if stage.amount > palletItemCount then
                return stage
            end
        end

    elseif mode == "Previous" then
        local previousStage = nil
        for _, stage in ipairs(data.stages) do
            if stage.amount < palletItemCount then
                if not previousStage or stage.amount > previousStage.amount then
                    previousStage = stage
                end
            end
        end
        return previousStage
    end
end

local function GetLowestAvailableStage(available, stages, palletItemCount)
    local lowestStage = nil

    for _, stage in ipairs(stages) do
        if stage.amount < palletItemCount then
            local required = palletItemCount - stage.amount

            if available >= required then
                if not lowestStage or stage.amount < lowestStage.amount then
                    lowestStage = stage
                end
            end
        end
    end

    return lowestStage
end

local function GetHighestAvailableStage(available, stages, palletItemCount)
    local highestStage = nil

    for _, stage in ipairs(stages) do
        if stage.amount > palletItemCount then
            local required = stage.amount - palletItemCount

            if available >= required then
                if not highestStage or stage.amount > highestStage.amount then
                    highestStage = stage
                end
            end
        end
    end

    return highestStage
end

local function CreateEmpty_PalletMenus(self, categoryMenus, data, propertyData)
    local nextStage = GetStage("Next", data, self.movableData.total)
    if not nextStage then return end

    local category = data.category or "Other"
    local categoryMenu = UI_GetOrCreateSubMenu(self.palletMenu, categoryMenus, "H3_PalletCategory_Add_" .. category)
    local addAmount = nextStage.amount - self.movableData.total
    UI_CreateItemOption(self, categoryMenu, data, nextStage, "AddItem", addAmount, "H3_PalletItem_Add", propertyData)

    -- if pallet has more than 1 nextStage left then create an AddAll option
    local highestStage = GetHighestAvailableStage(propertyData.count, data.stages, self.movableData.total)
    if highestStage and highestStage.amount > nextStage.amount then
        local addAllAmount = highestStage.amount - self.movableData.total
        UI_CreateItemOption(self, categoryMenu, data, highestStage, "AddItem", addAllAmount, "H3_PalletItem_AddAll", propertyData)
    end
end

local function CreateAdd_PalletMenu(self, actionMenus, data, propertyData)
    local currentStage = GetStage("Current", data, self.movableData.total)
    if not currentStage then return end

    -- if pallet has nextStage then create an Add actionMenu and Add -> Item option
    local nextStage = GetStage("Next", data, self.movableData.total)
    if not nextStage then return end

    if not actionMenus.Add then
        actionMenus.Add = UI_GetOrCreateSubMenu(self.palletMenu, actionMenus, "H3_PalletAction_Add")
    end

    local addAmount = nextStage.amount - self.movableData.total
    UI_CreateItemOption(self, actionMenus.Add, data, nextStage, "AddItem", addAmount, "H3_PalletItem_Add", propertyData)

    -- if pallet has more than 1 nextStage left then create an AddAll option
    local highestStage = GetHighestAvailableStage(propertyData.count, data.stages, self.movableData.total)
    if highestStage and highestStage.amount > nextStage.amount then
        local addAllAmount = highestStage.amount - self.movableData.total
        UI_CreateItemOption(self, actionMenus.Add, data, highestStage, "AddItem", addAllAmount, "H3_PalletItem_AddAll", propertyData)
    end
end

local function CreateRemove_PalletMenu(self, actionMenus, data, propertyData)
    local currentStage = GetStage("Current", data, self.movableData.total)
    if not currentStage then return end

    -- if pallet has previousStage then create an Remove actionMenu and Remove -> Item option
    local previousStage = GetStage("Previous", data, self.movableData.total)
    if not previousStage then return end

    if not actionMenus.Remove then
        actionMenus.Remove = UI_GetOrCreateSubMenu(self.palletMenu, actionMenus, "H3_PalletAction_Remove")
    end

    local removeAmount = self.movableData.total - previousStage.amount
    UI_CreateItemOption(self, actionMenus.Remove, data, previousStage, "RemoveItem", removeAmount, "H3_PalletItem_Remove", propertyData)

    -- if pallet has more than 1 previousStage left then create an RemoveAll option
    local lowestStage = GetLowestAvailableStage(propertyData.count, data.stages, self.movableData.total)
    if lowestStage and lowestStage.amount < previousStage.amount then
        local removeAllAmount = self.movableData.total - lowestStage.amount
        UI_CreateItemOption(self, actionMenus.Remove, data, lowestStage, "RemoveItem", removeAllAmount, "H3_PalletItem_RemoveAll", propertyData)
    end
end

-- ============================================================================
-- H3_Pallet Class and its helpers
-- ============================================================================

-- returns iterable table for ordering items in context menu
local function SortPropertyValues(ptable)
    if ptable["normal"] then
        return {"normal"}
    end

    local values = {}

    for key in pairs(ptable) do
        table.insert(values, key)
    end

    table.sort(values)

    return values

end

-- constructs PalletContextMenu based on available data
function H3_Pallet:constructMenu()
    debugH3.log("Client | RUN: constructMenu()")

    -- create the main context option for the pallet
    local palletMenu = UI_GetOrCreateSubMenu(self.context, {}, "H3_InteractPallet", "media/textures/Item_EmptyPallet.png")
    if not palletMenu then
        self.error = "Failed to create Initial palletMenu"
        return false
    end

    self.palletMenu = palletMenu
    local categoryMenus = {}
    local actionMenus = {}

    -- step through all the lookupTable entries
    for _, data in ipairs(self.lookupTable) do

        -- for each playerAvailableItem
        local playerAvailableItems = H3_GetAvailableItems(data.items, self.inventoryItems, self.groundItems)
        for itemType, propertyData in pairs(playerAvailableItems) do
            debugH3.log("PlayerAvailableItem: ", itemType)

            -- for each Item variant (condition or delta)
            local menuOrder = SortPropertyValues(propertyData.ptable)
            for _, value in ipairs(menuOrder) do
                local itemProperty = {
                    type = itemType,
                    pname = propertyData.pname,
                    value = value,
                    count = propertyData.ptable[value],
                }
                debugH3.log("Property: " .. tostring(itemProperty.pname) .. " | Value: " .. tostring(itemProperty.value) .. " | Count: " .. tostring(itemProperty.count))

                -- if pallet empty, create categoryMenus and their Add / AddAll item options
                if self.movableData.total == 0 then
                    CreateEmpty_PalletMenus(self, categoryMenus, data, itemProperty)

                -- else we need to create actionMenus for Add / Remove and their respective item options
                else
                    CreateAdd_PalletMenu(self, actionMenus, data, itemProperty)
                end
            end
        end

        -- if pallet has items to remove
        if self.movableData.total > 0 then

            -- for each palletAvailableItem
            local palletAvailableItems = self.movableData.ptable
            for itemType, propertyData in pairs(palletAvailableItems) do
                debugH3.log("PalletAvailableItem: ", itemType)

                -- for each Item variant (condition or delta)
                local menuOrder = SortPropertyValues(propertyData)
                for _, value in ipairs(menuOrder) do
                    local itemProperty = {
                        type = itemType,
                        pname = self.movableData.pname,
                        value = value,
                        count = propertyData[value],
                    }
                    debugH3.log("Property: " .. tostring(itemProperty.pname) .. " | Value: " .. tostring(itemProperty.value) .. " | Count: " .. tostring(itemProperty.count))

                    CreateRemove_PalletMenu(self, actionMenus, data, itemProperty)
                end
            end
        end
    end

    return true
end

-- returns true if it finds a same entry in both tables
local function isTable1_EntiryIn_Table2(table1, table2)
    if not table1 or not table2 then return end

    for _, filter in pairs(table2) do
        for key, _ in pairs(table1) do
            if key == filter then
                return true
            end
        end
    end
    return false
end

-- returns relevant snippets of the lookupTable
local function GetItemsTableForPallet(movableData, spriteName, isVanillaPallet)
    if isVanillaPallet then
        return vanillaPalletTable[spriteName]
    end

    if movableData then

        --[[ currently unused as no items have tags defined in modData
        -- if item has a tag then multiple returnTables
        local itemsTable = {}
        if movableData.tag then
            for _, data in ipairs(lookupTable) do
                if movableData.tag == data.tag then
                    itemsTable[#itemsTable + 1] = data
                end
            end
            return itemsTable
        end --]]

        -- one returnTable
        if movableData.fullTypes then
            for _, data in ipairs(itemLookup) do
                if isTable1_EntiryIn_Table2(movableData.fullTypes, data.items) then
                    return {data}
                end
            end
        end
    end

    debugH3.warn("Unknown item in pallet detected: ", movableData.fullTypes, "  in function GetItemsTableForPallet. Returning nil")
    return nil
end

-- gets inventory and ground itemsTables, gets lookupTable 
function H3_Pallet:getShared()
    debugH3.log("Client | RUN: getShared()")

    -- collect itemsTables
    local inventoryItems = self.player:getInventory()
    local groundItems = buildUtil.getMaterialOnGround(self.player:getSquare())

    if not inventoryItems and not groundItems then
        debugH3.log("No inventory or ground items found. Continuing safely.")
        -- not a fail since we still want to show greyed out Add options
    end

    self.inventoryItems = inventoryItems or {}
    self.groundItems = groundItems or {}

    -- filters the lookup to return relevant items only
    local lookupTable = GetItemsTableForPallet(self.movableData, self.spriteName, self.isVP)

    if not lookupTable then
        self.error = "Missing lookupTable."
        return false
    end

    self.lookupTable = lookupTable

    return true
end

-- returns movableData after reading or creating modData
local function GetSpriteObj_ModData(modData, spriteName, isVanillaPallet)
    -- if its an empty pallet it wont have modData so return default
    if spriteName == keys.vEmptyPallet then
        return {
            fullTypes = nil,
            total = 0,
            pname = "normal",
            ptable = {},
        }
    end

    local movableData = modData and modData.movableData
    if movableData then
        local fullTypes = movableData.H3_itemFullTypes or {}
        local total = movableData.H3_itemTotal or 0
        local fallback = {}
        for _, key in pairs(fullTypes) do
            fallback = { [key] = { normal = total, }, }
        end

        return {
            fullTypes = fullTypes,
            total = total,
            pname = movableData.H3_itemProperty or "normal",
            ptable = movableData.H3_itemPropertyData or fallback
        }
    end

    -- if pallet doesn't have modData then we need to construct it from spriteName (this will only run for vanilla pallets)
    if spriteName then
        if isVanillaPallet then
            local itemsTable = vanillaPalletTable[spriteName] or {}
            for _, data in ipairs(itemsTable) do
                for _, stage in ipairs(data.stages) do
                    if spriteName == stage.resultSprite then
                        local fullTypes = data.items or {}
                        local total = stage.amount or 0
                        local ptable = {}
                        for _, key in pairs(fullTypes) do
                            ptable = { [key] = { normal = total, }, }
                        end

                        return {
                            fullTypes = fullTypes,
                            total = total,
                            pname = "normal",
                            ptable = ptable
                        }
                    end
                end
            end
        end
    end

    debugH3.warn("Unknown modData for spriteName:  ", spriteName, "  Returning nil")
    return nil
end

-- gets spriteName, gets pallet modData.movable
function H3_Pallet:getClient()
    debugH3.log("Client | RUN: getClient()")

    -- get spriteName
    local sprite = self.pallet:getSprite()
    self.spriteName = sprite and sprite:getName()
    debugH3.log("Pallet sprite:  ", self.spriteName)

    if not self.spriteName then
        self.error = "Missing spriteName."
        return false
    end

    -- read in pallet modData.movable values (only modData.movable travels with the pallet when its picked up, regular modData gets lost)
    self.movableData = GetSpriteObj_ModData(self.pallet:getModData(), self.spriteName, self.isVP)
    debugH3.log("Clientside movableData | Items:  ", self.movableData.fullTypes)
    debugH3.log("Total:" .. tostring(self.movableData.total) .. " | pname: " .. tostring(self.movableData.pname) .. " | ptable: " .. tostring(self.movableData.ptable))

    if not self.movableData then
        self.error = "Missing / failed to construct movableData."
        return false
    end

    return true
end

function H3_Pallet:complete()
    debugH3.log("Client | RUN: complete()")

    if self.error then
        return false
    end

    if not self:getClient() then
        return false
    end

    if not self:getShared() then
        return false
    end

    if not self:constructMenu() then
        return false
    end

    debugH3.log("Pallet Context Menu:  ", "Success!")

    return true
end

function H3_Pallet:sendRequest(sprite, amount, propertyData, mode)
    debugH3.log("Client | RUN: sendRequest()")
    if mode == "AddItem" then
        -- collect itemsTables again (refreshing because self could be stale now)
        local inventoryItems = self.player:getInventory()
        local groundItems = buildUtil.getMaterialOnGround(self.player:getSquare())

        -- check players' available items again
        local availableItems = H3_GetAvailableItems(propertyData.type, inventoryItems, groundItems)
        local value = propertyData.value

        local specificPropertyCount = availableItems[propertyData.type].ptable[value] or 0
        if amount > specificPropertyCount then
            debugH3.warn("Player no longer has access to enough available items. Available: ", specificPropertyCount, "  Required: " .. tostring(amount))
            return
        end

    elseif mode == "RemoveItem" then
        -- pallet content verification code here
        amount = -amount
    end
    debugH3.log("SEND " .. tostring(mode) .. "  " .. tostring(propertyData.type) .. " with " .. tostring(propertyData.pname) .. ": "
        .. tostring(propertyData.value) .. " Available: " .. tostring(propertyData.count) .. " Required: " .. tostring(math.abs(amount)))

    if clientDebug then
        debugH3.log("clientDebug is enabled, halting :sendRequest() and exiting.")
        return
    end

	if luautils.walkAdj(self.player, self.pallet:getSquare(), false) then
		ISTimedActionQueue.add(H3_InteractPallet:new(self.player, self.pallet, self.pallet:getSquare(), sprite, propertyData.type, propertyData.pname, propertyData.value, amount, self.movableData))
	end

    return true
end

function H3_Pallet:new(contextMenu, playerObj, worldObj, isVanillaPallet)
    local o = setmetatable({}, H3_Pallet)
    o.error = nil

    -- from hook
    o.context = contextMenu
    o.player = playerObj
    o.pallet = worldObj
    o.isVP = isVanillaPallet

    if not o.context or not o.player or not o.pallet then
        o.error = "Invalid context / player / pallet"
    end

    -- from :getClient()
    o.spriteName = "verified"    -- source of truth if no movableData
    o.movableData = "verified"

    -- from :getShared()
    o.inventoryItems = nil       -- itemsTable = inventoryItems:getAllTypeRecurse( itemFullType )    to filter this
    o.groundItems = nil          -- itemsTable = groundItems[ itemFullType ]                         to filter this
    o.lookupTable = "verified"

    -- made in :constructMenu()
    o.palletMenu = "verified"


    if not o:complete() then
        debugH3.error(o.error, "  [H3_PalletClient.lua] is returning safely.")
    end

    return o
end

-- ============================================================================
-- Hook for ContextMenu entry point
-- ============================================================================

-- returns bool for match, bool for isVP
function CheckSpriteName(spriteName)
    if not spriteName then
        return false, false
    end

    if spriteName:find(import.keys.h3_spriteKey) then
        return true, false -- false here is for isVanillaPallet
    else
        for _, key in pairs(import.keys) do
            if spriteName == key then
                return true, true
            end
        end
    end
end

-- executes when OnFillWorldObjectContextMenu and calls H3_Pallet:new() if the square has eligble sprite
local function Hook_OnRightClick(playerID, context, worldobjects, test)
    if not playerID or not context or not worldobjects or test then return end

    -- get all objects in square
    for _, object in ipairs(worldobjects) do
        if object and object:getSquare() then
            local square = object:getSquare()
            local objects = square:getObjects()

            -- for each object in square
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)

                -- check spriteName against registered keys
                local spriteName = obj and obj:getSprite() and obj:getSprite():getName()
                local match, isVP = CheckSpriteName(spriteName)
                if match then
                    H3_Pallet:new(context, getSpecificPlayer(playerID), obj, isVP)
                    return
                end
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(Hook_OnRightClick)