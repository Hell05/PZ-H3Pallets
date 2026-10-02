--[[
BSMP_ContextMenuCode = {}

local materials = require("BSMP_DefineMaterials")

local goldResolver = {
    {
        item = "Base.GoldBar",
        icon = "Item_Ingot_Gold.png",
        stages = {
            {amount =  0, resultSprite = "construction_01_5"},
            {amount = 40, resultSprite = "bsmp_pallet_02_7"},
            {amount = 45, resultSprite = "location_military_knox_01_1"},
            {amount = 50, resultSprite = "bsmp_pallet_02_9"},
            {amount = 55, resultSprite = "bsmp_pallet_02_10"},
            {amount = 60, resultSprite = "bsmp_pallet_02_11"},
            {amount = 65, resultSprite = "bsmp_pallet_02_12"},
            {amount = 70, resultSprite = "bsmp_pallet_02_13"},
            {amount = 75, resultSprite = "bsmp_pallet_02_14"},
            {amount = 80, resultSprite = "bsmp_pallet_02_15"},
            {amount = 85, resultSprite = "bsmp_pallet_02_16"},
            {amount = 90, resultSprite = "bsmp_pallet_02_17"},
        },
    },
}

local function getCurrentStage(entity, data)
    if not entity then return end

    local sprite = entity:getSprite()
    if not sprite then return end

    local spriteName = sprite:getName()
    for _, stage in ipairs(data.stages) do
        if stage.resultSprite == spriteName then
            return stage
        end
    end

    return nil
end

local function getPreviousStage(data, currentAmount)
    local previousStage = nil
    for _, stage in ipairs(data.stages) do
        if stage.amount < currentAmount then
            if not previousStage or stage.amount > previousStage.amount then
                previousStage = stage
            end
        end
    end

    return previousStage
end

local function addSubMenuOption(subMenu, playerObj, entity, data, stage, mode, amount, textKey)
    -- construct the translation friendly context menu option text
    if data.useDelta == 0 then textKey = textKey .. "Empty" end
    local displayText = getText(textKey, amount, getItemNameFromFullType(data.item))
    local option = subMenu:addOption(
        displayText,
        playerObj,
        BSMP_ContextMenuCode[mode],
        entity,
        stage.resultSprite,
        data.item,
        amount,
        data.useDelta
    )
    option.iconTexture = getTexture(data.icon)

    if mode == "AddItem" then
        if amount > BSMP_playerRequiredItems(playerObj, data.item, data.useDelta) then
            option.notAvailable = true
        end
    end

    return option
end

local function getHighestAvailableStage(playerObj, data, currentAmount)
    local available = BSMP_playerRequiredItems(playerObj, data.item, data.useDelta)
    local highestStage = nil

    for _, stage in ipairs(data.stages) do
        if stage.amount > currentAmount then
            local required = stage.amount - currentAmount

            if available >= required then
                if not highestStage or stage.amount > highestStage.amount then
                    highestStage = stage
                end
            end
        end
    end

    return highestStage
end

local function getMaterialTableForPallet(pallet)
    local materialTable = materials

    if pallet then
        local sprite = pallet:getSprite()

        -- this is a dirty fix for the vanilla gold pallet to convert it into modded gold pallet
        if sprite and sprite:getName() == "location_military_knox_01_1" then
            materialTable = goldResolver
        end
    end

    return materialTable
end

function BSMP_ContextMenuCode.AddItem(character, entity, resultSprite, item, amount, delta)
    if amount > BSMP_playerRequiredItems(character, item, delta) then return end

	if luautils.walkAdj(character, entity:getSquare(), false) then
		ISTimedActionQueue.add(BSMP_InteractPallet:new(character, entity, entity:getSquare(), resultSprite, item, amount, delta));
	end
end

function BSMP_ContextMenuCode.RemoveItem(character, entity, resultSprite, item, amount, delta)

    if luautils.walkAdj(character, entity:getSquare(), false) then
        ISTimedActionQueue.add(BSMP_InteractPallet:new(character, entity, entity:getSquare(), resultSprite, item, -amount, delta));
    end
end

local function getOrCreateCategorySubMenu(parentMenu, categoryMenus, category)
    category = category or "Other"
    local textKey = "ContextMenu_PalletCategory_" .. category
    local displayCategory = getText(textKey)
    local subMenu = categoryMenus[category]
    if not subMenu then
        local option = parentMenu:addOption(displayCategory)
        subMenu = ISContextMenu:getNew(parentMenu)
        parentMenu:addSubMenu(option, subMenu)

        categoryMenus[category] = subMenu
    end

    return subMenu
end

function BSMP_ContextMenuCode.AddToEmptyPallet(context, param)

    local option = param.option
    local pallet = param.entity
    local playerObj = param.playerObj

    option.iconTexture = getTexture("media/textures/Item_EmptyPallet.png")

    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(option, subMenu)

    local materialTable = getMaterialTableForPallet(pallet)
    local categoryMenus = {}

    for _, data in ipairs(materialTable) do
        -- get the amount of items on pallet
        local currentStage = getCurrentStage(pallet, data)
        if currentStage then
            local currentAmount = currentStage.amount
            local nextStage = nil

            for _, stage in ipairs(data.stages) do
                if stage.amount > currentAmount then
                    nextStage = stage
                    break
                end
            end

            -- get stage above the current stage, if it exists add submenu option
            if nextStage then
                local addAmount = nextStage.amount - currentAmount
                local categoryMenu = getOrCreateCategorySubMenu(subMenu, categoryMenus, data.category)
                addSubMenuOption(categoryMenu, playerObj, pallet, data, nextStage, "AddItem", addAmount, "ContextMenu_Pallet_AddItem")

                -- if the pallet has more than 1 stage still available to be filled then add an Add All option
                local highestStage = getHighestAvailableStage(playerObj, data, currentAmount)
                if highestStage and highestStage.amount > nextStage.amount then

                    local addAllAmount = highestStage.amount - currentAmount
                    addSubMenuOption(categoryMenu, playerObj, pallet, data, highestStage, "AddItem", addAllAmount, "ContextMenu_Pallet_AddAll")
                end
            end
        end
    end
end

function BSMP_ContextMenuCode.AddToPallet(context, param)

    local option = param.option
    local pallet = param.entity
    local playerObj = param.playerObj

    option.iconTexture = getTexture("media/textures/Item_EmptyPallet.png")

    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(option, subMenu)

    local materialTable = getMaterialTableForPallet(pallet)

    for _, data in ipairs(materialTable) do
        -- get the amount of items on pallet
        local currentStage = getCurrentStage(pallet, data)
        if currentStage then
            local currentAmount = currentStage.amount
            local nextStage = nil

            for _, stage in ipairs(data.stages) do
                if stage.amount > currentAmount then
                    nextStage = stage
                    break
                end
            end

            -- get stage above the current stage, if it exists add submenu option
            if nextStage then
                local addAmount = nextStage.amount - currentAmount
                addSubMenuOption(subMenu, playerObj, pallet, data, nextStage, "AddItem", addAmount, "ContextMenu_Pallet_AddItem")

                -- if the pallet has more than 1 stage still available to be filled then add an Add All option
                local highestStage = getHighestAvailableStage(playerObj, data, currentAmount)
                if highestStage and highestStage.amount > nextStage.amount then

                    local addAllAmount = highestStage.amount - currentAmount
                    addSubMenuOption(subMenu, playerObj, pallet, data, highestStage, "AddItem", addAllAmount, "ContextMenu_Pallet_AddAll")
                end
            end
        end
    end
end

function BSMP_ContextMenuCode.RemoveFromPallet(context, param)

    local option = param.option
    local pallet = param.entity
    local playerObj = param.playerObj

    option.iconTexture = getTexture("media/textures/Item_EmptyPallet.png")

    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(option, subMenu)

    local materialTable = getMaterialTableForPallet(pallet)

    for _, data in ipairs(materialTable) do
        -- get the amount of items on pallet
        local currentStage = getCurrentStage(pallet, data)
        if currentStage and currentStage.amount > 0 then
            local currentAmount = currentStage.amount

            -- get stage below the current stage, if it exists add submenu option
            local previousStage = getPreviousStage(data, currentAmount)
            if previousStage then
                local removeAmount = currentAmount - previousStage.amount
                addSubMenuOption(subMenu, playerObj, pallet, data, previousStage, "RemoveItem", removeAmount, "ContextMenu_Pallet_RemoveItem")

                -- if the pallet has more than 1 stage still available to be removed then add a Remove All option
                local emptyStage = data.stages[1]
                local removeAllAmount = currentAmount - emptyStage.amount
                if removeAllAmount > removeAmount then
                    addSubMenuOption(subMenu, playerObj, pallet, data, emptyStage, "RemoveItem", removeAllAmount, "ContextMenu_Pallet_RemoveAll")
                end
            end
        end
    end
end
--]]