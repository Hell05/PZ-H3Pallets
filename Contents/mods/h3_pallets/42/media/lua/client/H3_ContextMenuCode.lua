---@diagnostic disable: undefined-global
-- ============================================================================
-- This file handles the client side context menu UI options
-- ============================================================================
-- Hey, this is Hell. A little context for this mod and its design process for
-- those that are interested (I assume you might be since you opened this file)

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

local DefineItemTables = require("H3_DefineItemTables")
local lookupTable = DefineItemTables.items
local keys = DefineItemTables.keys
local vanillaPalletTable = DefineItemTables.vanillaPalletTable
H3_ContextMenuCode = {}

-- debug toggle
local DEBUG = true

local function H3_Debug(mode, text)
    if not DEBUG then return end

    if mode == "log" then
        print("H3 Log: " .. text)
    elseif mode == "warn" then
        print("!!! WARN !!! " .. text)
    end
end

-- ============================================================================
-- Authoritative Triggers -- disabled for now
-- ============================================================================

-- called when a PalletMenu ->   Add  -> ItemOption is clicked
function H3_ContextMenuCode.AddItem(character, entity, sprite, item, amount, propertyData)
    local availableItems = H3_PlayerRequiredItems(character, item)
    local value = propertyData.value

    if not availableItems then return end
    local specificPropertyCount = availableItems[item].properties[value]
    if amount > specificPropertyCount then return end

    if DEBUG then
        H3_Debug("log", "SEND AddItem" .. tostring(item) .. " " .. tostring(propertyData.count) .. " = " .. tostring(amount))
        return
    end

	if luautils.walkAdj(character, entity:getSquare(), false) then
		ISTimedActionQueue.add(H3_InteractPallet:new(character, entity, entity:getSquare(), sprite, item, amount, propertyData));
	end
end

-- called when a PalletMenu -> Remove -> ItemOption is clicked
function H3_ContextMenuCode.RemoveItem(character, entity, sprite, item, amount, propertyData)
    if DEBUG then
        H3_Debug("log", "SEND RemoveItem" .. tostring(item) .. " " .. tostring(propertyData.count) .. " = " .. tostring(-amount))
        return
    end
    if luautils.walkAdj(character, entity:getSquare(), false) then
        ISTimedActionQueue.add(H3_InteractPallet:new(character, entity, entity:getSquare(), sprite, item, -amount, propertyData));
    end
end

-- ============================================================================
-- UI Context Menu Constructors
-- ============================================================================

-- itemOption creator
local function UI_CreateItemOption(subMenu, player, entity, data, stage, mode, amount, actionName, propertyData)
    -- construct the translation friendly context menu option text
    local textKey = "ContextMenu_" .. actionName
    local displayText = getText(textKey, amount, getItemNameFromFullType(data.item))
    if propertyData.name ~= "normal" then
        textKey = "ContextMenu_" .. actionName .. "_Property"
        displayText = getText(textKey, amount, getItemNameFromFullType(data.item), propertyData.value)
    end

    local itemOption = subMenu:addOption(
        displayText,
        player,
        H3_ContextMenuCode[mode],
        entity,
        stage.resultSprite,
        data.item,
        amount,
        propertyData
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
    H3_Debug("warn", "No stage found in GetStage.")
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

local function CreateEmpty_PalletMenus(palletMenu, categoryMenus, pallet, player, data, palletItemCount, propertyData)
    local nextStage = GetStage("Next", data, palletItemCount)
    if not nextStage then return end

    local category = data.category or "Other"
    local categoryMenu = UI_GetOrCreateSubMenu(palletMenu, categoryMenus, "H3_PalletCategory_Add_" .. category)
    print("categoryMenu " .. tostring(categoryMenu))
    print("categoryMenus " .. tostring(categoryMenus))
    local addAmount = nextStage.amount - palletItemCount
    UI_CreateItemOption(categoryMenu, player, pallet, data, nextStage, "AddItem", addAmount, "H3_PalletItem_Add", propertyData)

    -- if pallet has more than 1 nextStage left then create an AddAll option
    local highestStage = GetHighestAvailableStage(propertyData.count, data.stages, palletItemCount)
    if highestStage and highestStage.amount > nextStage.amount then
        local addAllAmount = highestStage.amount - palletItemCount
        UI_CreateItemOption(categoryMenu, player, pallet, data, highestStage, "AddItem", addAllAmount, "H3_PalletItem_AddAll", propertyData)
    end
end

local function CreateAdd_PalletMenu(palletMenu, actionMenus, pallet, player, data, palletItemCount, propertyData)
    -- if pallet has nextStage then create an Add actionMenu and Add -> Item option
    local nextStage = GetStage("Next", data, palletItemCount)
    if not nextStage then return end

    if not actionMenus.Add then
        actionMenus.Add = UI_GetOrCreateSubMenu(palletMenu, actionMenus, "H3_PalletAction_Add")
    end

    local addAmount = nextStage.amount - palletItemCount
    UI_CreateItemOption(actionMenus.Add, player, pallet, data, nextStage, "AddItem", addAmount, "H3_PalletItem_Add", propertyData)

    -- if pallet has more than 1 nextStage left then create an AddAll option
    local highestStage = GetHighestAvailableStage(propertyData.count, data.stages, palletItemCount)
    if highestStage and highestStage.amount > nextStage.amount then
        local addAllAmount = highestStage.amount - palletItemCount
        UI_CreateItemOption(actionMenus.Add, player, pallet, data, highestStage, "AddItem", addAllAmount, "H3_PalletItem_AddAll", propertyData)
    end
end

local function CreateRemove_PalletMenu(palletMenu, actionMenus, pallet, player, data, palletItemCount, propertyData)
    -- if pallet has previousStage then create an Remove actionMenu and Remove -> Item option
    local previousStage = GetStage("Previous", data, palletItemCount)
    if not previousStage then return end

    if not actionMenus.Remove then
        actionMenus.Remove = UI_GetOrCreateSubMenu(palletMenu, actionMenus, "H3_PalletAction_Remove")
    end

    local removeAmount = palletItemCount - previousStage.amount
    UI_CreateItemOption(actionMenus.Remove, player, pallet, data, previousStage, "RemoveItem", removeAmount, "H3_PalletItem_Remove", propertyData)

    -- if pallet has more than 1 previousStage left then create an RemoveAll option
    local emptyStage = data.stages[1]
    local removeAllAmount = palletItemCount - propertyData.count
    if removeAllAmount > removeAmount then
        UI_CreateItemOption(actionMenus.Remove, player, pallet, data, emptyStage, "RemoveItem", removeAllAmount, "H3_PalletItem_RemoveAll", propertyData)
    end
end

-- Constructs all the pallet context menu options
local function ConstructPalletMenu(palletMenu, pallet, player, itemsTable, itemData)
    if not palletMenu or not pallet or not player or not itemsTable then return end
    local palletItemCount = itemData.count
    H3_Debug("log", "-- Executing ConstructPalletMenu --")

    local categoryMenus = {}
    local actionMenus = {}

    for _, data in ipairs(itemsTable) do
        local availableItems = H3_PlayerRequiredItems(player, data.item)
        if availableItems then
            for itemName, propertyData in pairs(availableItems) do
                H3_Debug("log", "Item: " .. tostring(itemName))

                for value, count in pairs(propertyData.properties) do
                    local params = {
                        name = propertyData.property,
                        value = value,
                        count = count,
                    }
                    H3_Debug("log", "Property: " .. tostring(params.name) .. " | Value: " .. tostring(params.value) .. " | Count: " .. tostring(params.count))

                    -- if pallet empty, create category menus and their Add / AddAll item options
                    if palletItemCount == 0 then
                        CreateEmpty_PalletMenus(palletMenu, categoryMenus, pallet, player, data, palletItemCount, params)

                    -- else we need to create action menus for Add / Remove and their respective item options
                    else
                        local currentStage = GetStage("Current", data, palletItemCount)
                        if currentStage then
                            CreateAdd_PalletMenu(palletMenu, actionMenus, pallet, player, data, palletItemCount, params)
                            CreateRemove_PalletMenu(palletMenu, actionMenus, pallet, player, data, palletItemCount, params)
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- Vanilla Pallet Resolver (lets us use vanilla pallets as entry points too)
-- ============================================================================

local function ConstructItemsData(modData, spriteName, isVanillaPallet)
    -- if its an empty pallet it wont have modData so return empty
    if spriteName == keys.vEmptyPallet then
        return {
            tag = nil,
            type = nil,
            count = 0,
            properties = {},
        }
    end

    local movableData = modData.movableData
    if movableData then
        return {
            tag = movableData.H3_itemTag or nil,
            type = movableData.H3_itemType or nil,
            count = movableData.H3_itemCount or 0,
            properties = movableData.H3_itemProperties or {},
        }
    end

    -- if pallet doesn't have modData then we need to construct it from spriteName
    if spriteName then
        local itemsTable = lookupTable
        if isVanillaPallet and vanillaPalletTable then
            itemsTable = vanillaPalletTable[spriteName] or {}
        end

        for _, data in ipairs(itemsTable) do
            for _, stage in ipairs(data.stages) do
                if spriteName == stage.resultSprite then
                    return {
                        tag = data.tag or nil,
                        type = data.item or nil,
                        count = stage.amount or 0,
                        properties = data.properties or {},
                    }
                end
            end
        end
    end

    H3_Debug("warn", ("Unknown spritename found: " .. tostring(spriteName) .. " in function ConstructItemsData. Returning {}"))
    return {}
end

local function GetItemsTableForPallet(itemData, spriteName, isVanillaPallet)
    if isVanillaPallet and spriteName then
        return vanillaPalletTable[spriteName]
    end

    -- for pallets with itemData we need to return only the stored item(s) table(s)
    if itemData then
        local itemsTable = {}
        -- if item has a tag its multiple itemTypes stored so return multiple
        if itemData.tag then
            for _, data in ipairs(lookupTable) do
                if itemData.tag == data.tag then
                    itemsTable[#itemsTable + 1] = data
                end
            end
            return itemsTable

        -- single item
        elseif itemData.type then
            for _, data in ipairs(lookupTable) do
                if itemData.type == data.item then
                    return {data}
                end
            end
        end
    end

    H3_Debug("warn", ("Unknown item  found: " .. tostring(itemData) .. " stored in sprite: "  .. tostring(spriteName) .. " in function GetItemsTableForPallet. Returning {}"))
    return {}
end

-- ============================================================================
-- Context Menu Entry Handlers
-- ============================================================================

function H3_ContextMenuCode.InteractPallet(context, player, pallet, isVanillaPallet)
    H3_Debug("log", "RUN InteractPallet")
    local sprite = pallet:getSprite()
    if not sprite or not sprite:getName() then return end
    local spriteName = sprite:getName()
    H3_Debug("log", ("Pallet sprite: " .. tostring(spriteName)))

    -- read in pallet modData
    local itemData = ConstructItemsData(pallet:getModData(), spriteName, isVanillaPallet)
    H3_Debug("log", ("Pallet itemData: " .. tostring(itemData)))

    local itemsTable = GetItemsTableForPallet(itemData, spriteName, isVanillaPallet)
    H3_Debug("log", ("itemsTable type: " .. type(itemsTable)))

    -- create the main context option for the pallet
    local palletMenu = UI_GetOrCreateSubMenu(context, {}, "H3_InteractPallet", "media/textures/Item_EmptyPallet.png")

    ConstructPalletMenu(palletMenu, pallet, player, itemsTable, itemData)
end

-- executes OnFillWorldObjectContextMenu and calls H3_ContextMenuCode.InteractPallet if the square has eligble sprite
local function onRightClick(playerID, context, worldobjects, test)
    if not playerID or not context or not worldobjects or test then return end

    for _, object in ipairs(worldobjects) do
        if object and object:getSquare() then
            local square = object:getSquare()
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do

                local obj = objects:get(i)
                if obj then
                    local sprite = obj:getSprite()
                    if sprite then

                        -- check spriteName against registered keys
                        local spriteName = sprite:getName()
                        if spriteName:find(keys.h3_spriteKey) then
                            H3_ContextMenuCode.InteractPallet(context, getSpecificPlayer(playerID), obj, false) -- false here is for isVanillaPallet
                            return
                        else
                            for _, key in pairs(keys) do
                                if spriteName == key then
                                    H3_ContextMenuCode.InteractPallet(context, getSpecificPlayer(playerID), obj, true)
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onRightClick)