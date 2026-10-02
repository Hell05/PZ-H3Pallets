-- ============================================================================
-- This file handles the client side context menu UI options
-- ============================================================================

H3_ContextMenuCode = {}
local lookupTable = require("H3_DefineItemTables")

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

local function GetItemsTableForPallet(itemType)
    if not itemType then
        return lookupTable
    end

    for _, data in ipairs(lookupTable) do
        if itemType == data.item then
            return {data}
        end
    end

    DebugType.Mod:warn("Unknown itemType in pallet found: " .. tostring(itemType) .. " in function GetItemsTableForPallet. Returning {}")
    return {}
end

-- itemOption creator
local function UI_CreateItemOption(subMenu, player, entity, data, stage, mode, amount, actionName, available)
    -- construct the translation friendly context menu option text
    local textKey = "ContextMenu_" .. actionName .. (data.useDelta == 0 and "Empty" or "")
    local displayText = getText(textKey, amount, getItemNameFromFullType(data.item))

    local itemOption = subMenu:addOption(
        displayText,
        player,
        H3_ContextMenuCode[mode],
        entity,
        stage.overlaySprite,
        data.item,
        amount,
        data.useDelta
        )
    itemOption.iconTexture = getTexture(data.icon)

    if available then
        if amount > available then
            itemOption.notAvailable = true
        end
    end

    return itemOption
end

-- PalletMenu -> Add/Remove subMenu creator
local function UI_GetOrCreateSubMenu(parentMenu, subMenus, menuName)
    if not parentMenu then return end

    local subMenu = subMenus[menuName]
    if not subMenu then
        local textKey = "ContextMenu_" .. menuName
        local displayText = getText(textKey)

        local option = parentMenu:addOption(displayText)
        subMenu = ISContextMenu:getNew(parentMenu)
        parentMenu:addSubMenu(option, subMenu)

        subMenus[menuName] = subMenu
    end

    return subMenu
end

-- Constructs all the pallet context menu options
local function ConstructPalletMenu(palletMenu, pallet, player, itemsTable, palletItemCount)
    if not palletMenu or not pallet or not player or not itemsTable then return end
    print("-- Executing ConstructPalletMenu --")

    local categoryMenus = {}
    local actionMenus = {}

    for _, data in ipairs(itemsTable) do
        local available = H3_PlayerRequiredItems(player, data.item, data.useDelta)

        -- if pallet empty, create category menus and only create Add / AddAll item options
        if palletItemCount == 0 then
            local nextStage = GetStage("Next", data, palletItemCount)
            if nextStage then

                local category = data.category or "Other"
                local categoryMenu = UI_GetOrCreateSubMenu(palletMenu, categoryMenus, "H3PalletCategory_Add_" .. category)

                local addAmount = nextStage.amount - palletItemCount
                UI_CreateItemOption(categoryMenu, player, pallet, data, nextStage, "AddItem", addAmount, "H3PalletItem_Add", available)

                -- if pallet has more than 1 nextStage left then create an AddAll option
                local highestStage = GetHighestAvailableStage(available, data.stages, palletItemCount)
                if highestStage and highestStage.amount > nextStage.amount then
                    local addAllAmount = highestStage.amount - palletItemCount
                    UI_CreateItemOption(categoryMenu, player, pallet, data, highestStage, "AddItem", addAllAmount, "H3PalletItem_AddAll", available)
                end
            end


        -- else we need to create the action menus for Add / Remove and their subMenu options
        else
            local currentStage = GetStage("Current", data, palletItemCount)
            if currentStage then

                -- if pallet has nextStage then create an Add actionMenu and Add -> Item option
                local nextStage = GetStage("Next", data, palletItemCount)
                if nextStage then

                    if not actionMenus.Add then
                        actionMenus.Add = UI_GetOrCreateSubMenu(palletMenu, actionMenus, "H3PalletAction_Add")
                    end

                    local addAmount = nextStage.amount - palletItemCount
                    UI_CreateItemOption(actionMenus.Add, player, pallet, data, nextStage, "AddItem", addAmount, "H3PalletItem_Add", available)

                    -- if pallet has more than 1 nextStage left then create an AddAll option
                    local highestStage = GetHighestAvailableStage(available, data.stages, palletItemCount)
                    if highestStage and highestStage.amount > nextStage.amount then
                        local addAllAmount = highestStage.amount - palletItemCount
                        UI_CreateItemOption(actionMenus.Add, player, pallet, data, highestStage, "AddItem", addAllAmount, "H3PalletItem_AddAll", available)
                    end
                end


                -- if pallet has previousStage then create an Remove actionMenu and Remove -> Item option
                local previousStage = GetStage("Previous", data, palletItemCount)
                if previousStage then

                    if not actionMenus.Remove then
                        actionMenus.Remove = UI_GetOrCreateSubMenu(palletMenu, actionMenus, "H3PalletAction_Remove")
                    end

                    local removeAmount = palletItemCount - previousStage.amount
                    UI_CreateItemOption(actionMenus.Remove, player, pallet, data, previousStage, "RemoveItem", removeAmount, "H3PalletItem_Remove")

                    -- if pallet has more than 1 previousStage left then create an RemoveAll option
                    local emptyStage = data.stages[1]
                    local removeAllAmount = palletItemCount - emptyStage.amount
                    if removeAllAmount > removeAmount then
                        UI_CreateItemOption(actionMenus.Remove, player, pallet, data, emptyStage, "RemoveItem", removeAllAmount, "H3PalletItem_RemoveAll")
                    end
                end
            end
        end
    end
end

-- called when a PalletMenu ->   Add  -> ItemOption is actually clicked (this is what triggers authorative code)
function H3_ContextMenuCode.AddItem(character, entity, overlaySprite, item, amount, delta)
    if amount > H3_PlayerRequiredItems(character, item, delta) then return end

	if luautils.walkAdj(character, entity:getSquare(), false) then
		ISTimedActionQueue.add(H3_InteractPallet:new(character, entity, entity:getSquare(), overlaySprite, item, amount, delta));
	end
end

-- called when a PalletMenu -> Remove -> ItemOption is actually clicked (this is what triggers authorative code)
function H3_ContextMenuCode.RemoveItem(character, entity, overlaySprite, item, amount, delta)

    if luautils.walkAdj(character, entity:getSquare(), false) then
        ISTimedActionQueue.add(H3_InteractPallet:new(character, entity, entity:getSquare(), overlaySprite, item, -amount, delta));
    end
end

-- main pallet interaction handler that all pallets call from entity
function H3_ContextMenuCode.InteractPallet(context, param)
    local option = param.option
    local pallet = param.entity
    local player = param.playerObj
    local itemType = nil
    local palletItemCount = 0

    local modData = pallet:getModData()
    local movableData = modData.movableData

    if movableData then
        itemType = movableData.H3_itemType or nil
        palletItemCount = movableData.H3_itemCount or 0
    end

    local itemsTable = GetItemsTableForPallet(itemType)

    print("H3:",
        "  Type: ", movableData and movableData.H3_itemType,
        "  Count: ", movableData and movableData.H3_itemCount,
        "  Sprite: ", movableData and movableData.H3_overlaySprite)

    local sprite = pallet:getSprite()
    local overlay = pallet:getOverlaySprite()
    if not sprite then return end

    print("Pallet sprite: " .. tostring(sprite and sprite:getName()))
    print("Overlay sprite: " .. tostring(overlay and overlay:getName()))

    -- create the main context option for the pallet
    option.iconTexture = getTexture("media/textures/Item_EmptyPallet.png")
    local palletMenu = ISContextMenu:getNew(context)
    context:addSubMenu(option, palletMenu)

    ConstructPalletMenu(palletMenu, pallet, player, itemsTable, palletItemCount)
end

--[[
Events.OnPreFillWorldObjectContextMenu.Add(function(player, context, worldobjects, test)
    if test then return end
    local param = {
        player = getSpecificPlayer(player),
        option = "PalletMenu",
        worldobjects = worldobjects,
    }

    -- worldobjects contains the IsoObjects on the clicked square
    for _, object in ipairs(worldobjects) do
        if object and object:getSquare() then
            local square = object:getSquare()

            -- inspect objects on this square
            local objects = square:getObjects()

            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)

                if obj then
                    local sprite = obj:getSprite()

                    if sprite then
                        local spriteName = sprite:getName()

                        -- Check whether this is one of your pallet sprites
                        if H3_IsPalletSprite(spriteName) then
                            H3_AddPalletContextMenu(
                                player,
                                context,
                                obj
                            )
                        end
                    end
                end
            end
        end
    end
end) --]]