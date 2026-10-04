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

local debugMode = true
local debugLogging = true

local debugH3 = {}
function debugH3.log(text1, text2, text3)
    if debugLogging then print("[H3 Log]  ", tostring(text1 or "") .. tostring(text2 or "") .. tostring(text3 or "")) end
end
function debugH3.warn(text1, text2, text3)
    if debugLogging then print("[=== [H3 WARN] ===]  ", tostring(text1 or "") .. tostring(text2 or "") .. tostring(text3 or "")) end
end
function debugH3.error(text1, text2, text3) print("[!!! [H3 ERROR] !!!]  ", tostring(text1 or "") .. tostring(text2 or "") .. tostring(text3 or "")) end

-- ============================================================================

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
    local displayText = getText(textKey, amount, getItemNameFromFullType(propertyData.type))

    if propertyData.name == "delta" then
        textKey = textKey .. "_Delta"
        local value = string.format("%.0f", (propertyData.value * 100))
        displayText = getText(textKey, amount, getItemNameFromFullType(propertyData.type), value)

    elseif propertyData.name == "condition" then
        textKey = textKey .. "_Condition"
        local value = string.format("%.0f", propertyData.value )
        displayText = getText(textKey, amount, getItemNameFromFullType(propertyData.type), value)
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
    -- if pallet has previousStage then create an Remove actionMenu and Remove -> Item option
    local previousStage = GetStage("Previous", data, self.movableData.total)
    if not previousStage then return end

    if not actionMenus.Remove then
        actionMenus.Remove = UI_GetOrCreateSubMenu(self.palletMenu, actionMenus, "H3_PalletAction_Remove")
    end

    local removeAmount = self.movableData.total - previousStage.amount
    UI_CreateItemOption(self, actionMenus.Remove, data, previousStage, "RemoveItem", removeAmount, "H3_PalletItem_Remove", propertyData)

    -- if pallet has more than 1 previousStage left then create an RemoveAll option
    local emptyStage = data.stages[1]
    local removeAllAmount = propertyData.count
    if removeAllAmount > removeAmount then
        UI_CreateItemOption(self, actionMenus.Remove, data, emptyStage, "RemoveItem", removeAllAmount, "H3_PalletItem_RemoveAll", propertyData)
    end
end

-- ============================================================================
-- H3_Pallet Class and its helpers
-- ============================================================================

--[[ returns an item table such as e.g. 

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

-- returns a table of available items to iterate through
local function GetAvailableItems(itemInput, allInventoryItems, allGroundItems)
    if not itemInput then
        debugH3.log("itemInput: ", itemInput)
        return {}
    end

    -- if multiple items listed in itemType then generate a joint table
    if type(itemInput) == "table" then
        local resultTable = {}
        for _, item in ipairs(itemInput) do
            local result = GetAvailableItems(item, allInventoryItems, allGroundItems)
            if result then
                for itemKey, values in pairs(result) do
                    resultTable[itemKey] = values
                end
            end
        end
        return resultTable
    end

    -- else itemInput is a string so continue
    local itemType = itemInput
    local resultTable = {}

    -- check inventoryItems first
    local inventoryItems = allInventoryItems:getAllTypeRecurse(itemType)
    if inventoryItems then
        for i = 0, inventoryItems:size() - 1 do
            local item = inventoryItems:get(i)
            resultTable = GetItemProperties(item, resultTable)
        end
    end

    -- check groundItems next
    local groundItems = allGroundItems[itemType]
    if groundItems then
        for _, item in ipairs(groundItems) do
            resultTable = GetItemProperties(item, resultTable)
        end
    end

    -- if nothing is in resultTable the item is not available, default count to 0
    if not resultTable[itemType] then
        resultTable = { [itemType] = { property = "normal", properties = { normal = 0 } } }

        -- We still want the context entry for the item but we use default properties to prevent
        -- items that can have condition or delta values being displayed all values at all times.
        -- Instead we use a generic entry to group them and only show values if they are available
    end

    return resultTable
end

-- TODO return a list similar to GetAvailableItems but we have to use modData to construct it
local function GetPalletContents(movableData)
    return {}
end

-- constructs PalletContextMenu based on available data
function H3_Pallet:constructMenu()
    debugH3.log("RUN: constructMenu()")

    -- create the main context option for the pallet
    local palletMenu = UI_GetOrCreateSubMenu(self.context, {}, "H3_InteractPallet", "media/textures/Item_EmptyPallet.png")
    if not palletMenu then
        self.error = "Failed to create Initial palletMenu"
        return false
    end

    self.palletMenu = palletMenu
    debugH3.log("Pallet Context Menu:  ", self.palletMenu)

    local categoryMenus = {}
    local actionMenus = {}

    -- step through all the lookupTable entries
    for _, data in ipairs(self.lookupTable) do

        -- for each playerAvailableItem
        local playerAvailableItems = GetAvailableItems(data.items, self.inventoryItems, self.groundItems)
        debugH3.log("playerAvailableItems:  ", playerAvailableItems)
        for itemType, propertyData in pairs(playerAvailableItems) do
            debugH3.log("PlayerAvailableItem: ", itemType)

            -- for each Item variant (condition or delta)
            for value, count in pairs(propertyData.properties) do
                local itemProperty = {
                    type = itemType,
                    name = propertyData.property,
                    value = value,
                    count = count,
                }
                debugH3.log("Property: " .. tostring(itemProperty.name) .. " | Value: " .. tostring(itemProperty.value) .. " | Count: " .. tostring(itemProperty.count))

                -- if pallet empty, create categoryMenus and their Add / AddAll item options
                if self.movableData.total == 0 then
                    CreateEmpty_PalletMenus(self, categoryMenus, data, itemProperty)

                -- else we need to create actionMenus for Add / Remove and their respective item options
                else
                    local currentStage = GetStage("Current", data, self.movableData.total)
                    if currentStage then
                        CreateAdd_PalletMenu(self, actionMenus, data, itemProperty)
                        -- TODO: remove menu needs its own palletAvailableItems loop based on pallet contents once we have modData
                        CreateRemove_PalletMenu(self, actionMenus, data, itemProperty)
                    end
                end
            end
        end

        -- TODO: adapt this so its suitable for removing items from pallet, should skip currently.
        -- for each palletAvailableItem
        local palletAvailableItems = GetPalletContents(self.movableData)
        for itemType, propertyData in pairs(palletAvailableItems) do
            debugH3.log("PalletAvailableItem: ", itemType)

            -- for each Item variant (condition or delta)
            for value, count in pairs(propertyData.properties) do
                local itemProperty = {
                    type = itemType,
                    name = propertyData.property,
                    value = value,
                    count = count,
                }
                debugH3.log("Property: " .. tostring(itemProperty.name) .. " | Value: " .. tostring(itemProperty.value) .. " | Count: " .. tostring(itemProperty.count))

                if self.movableData.total > 0 then

                local currentStage = GetStage("Current", data, self.movableData.total)
                if currentStage then
                    -- TODO: remove menu needs its own palletAvailableItems loop based on pallet contents once we have modData
                    CreateRemove_PalletMenu(self, actionMenus, data, itemProperty)
                    end
                end
            end
        end
    end

    return true
end

-- returns true if it finds a same entry in both tables
local function isTable1_EntiryIn_Table2(table1, table2)
    if not table1 or not table2 then return end

    for _, filter in table2 do
        for _, key in table1 do
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
            for _, data in ipairs(lookupTable) do
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
    debugH3.log("RUN: getShared()")

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
    debugH3.log("lookupTable type: ", type(lookupTable))

    if not lookupTable then
        self.error = "Missing lookupTable."
        return false
    end

    self.lookupTable = lookupTable

    return true
end

-- returns movableData after reading or creating modData
local function getSpriteObj_ModData(modData, spriteName, isVanillaPallet)
    -- if its an empty pallet it wont have modData so return default
    if spriteName == keys.vEmptyPallet then
        return {
            fullTypes = nil,
            total = 0,
            properties = {},
        }
    end

    local movableData = modData and modData.movableData
    if movableData then
        return {
            fullTypes = movableData.H3_itemFullTypes or {},
            total = movableData.H3_itemTotal or 0,
            properties = movableData.H3_itemProperties or {},
        }
    end

    -- if pallet doesn't have modData then we need to construct it from spriteName
    if spriteName then
        local itemsTable = itemLookup
        if isVanillaPallet then
            itemsTable = vanillaPalletTable[spriteName] or {}
        end

        for _, data in ipairs(itemsTable) do
            for _, stage in ipairs(data.stages) do
                if spriteName == stage.resultSprite then
                    return {
                        fullTypes = data.items or {},
                        total = stage.amount or 0,
                        properties = {},
                    }
                end
            end
        end
    end

    debugH3.warn("Unknown spritename:  ", spriteName, "  in function ConstructItemsData. Returning nil")
    return nil
end

-- gets spriteName, gets pallet modData.movable
function H3_Pallet:getClient()
    debugH3.log("RUN: getClient()")

    -- get spriteName
    local sprite = self.pallet:getSprite()
    self.spriteName = sprite and sprite:getName()
    debugH3.log("Pallet sprite:  ", self.spriteName)

    if not self.spriteName then
        self.error = "Missing spriteName."
        return false
    end

    -- read in pallet modData.movable values (only modData.movable travels with the pallet when its picked up, regular modData gets lost)
    self.movableData = getSpriteObj_ModData(self.pallet:getModData(), self.spriteName, self.isVP)
    debugH3.log("Pallet movableData:  ", self.movableData)

    if not self.movableData then
        self.error = "Missing / failed to construct movableData."
        return false
    end

    return true
end

function H3_Pallet:complete()
    if self.error then
        return false
    end

    debugH3.log("RUN: complete()")

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
    debugH3.log("RUN: sendRequest()")
    if mode == "AddItem" then
        -- collect itemsTables again (refreshing because self could be stale now)
        local inventoryItems = self.player:getInventory()
        local groundItems = buildUtil.getMaterialOnGround(self.player:getSquare())

        -- check players' available items again
        local availableItems = GetAvailableItems(propertyData.type, inventoryItems, groundItems)
        local value = propertyData.value

        local specificPropertyCount = availableItems[propertyData.type].properties[value] or 0
        if amount > specificPropertyCount then
            debugH3.log("Player no longer has access to enough available items. Available: ", specificPropertyCount, "  Required: " .. tostring(amount))
            return
        end

    elseif mode == "RemoveItem" then
        -- pallet content verification code here
        amount = -amount
    end

    if debugMode then  -- remove if when contextMenu is done debugging
        debugH3.log("SEND " .. tostring(propertyData.type) .. " " .. tostring(propertyData.count) .. " = " .. tostring(amount), "  Successful")
        return
    end

	if luautils.walkAdj(self.player, self.pallet:getSquare(), false) then
		ISTimedActionQueue.add(H3_InteractPallet:new(self.player, self.pallet, self.pallet:getSquare(), sprite, propertyData.type, amount, propertyData));
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

    if not o.context or not o.player or not o.pallet or not o.isVP then
        o.error = "Invalid context / player / pallet / bool"
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

-- executes when OnFillWorldObjectContextMenu and calls H3_Pallet:new() if the square has eligble sprite
local function Hook_OnRightClick(playerID, context, worldobjects, test)
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
                            H3_Pallet:new(context, getSpecificPlayer(playerID), obj, false) -- false here is for isVanillaPallet
                            return
                        else
                            for _, key in pairs(keys) do
                                if spriteName == key then
                                    H3_Pallet:new(context, getSpecificPlayer(playerID), obj, true)
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

Events.OnFillWorldObjectContextMenu.Add(Hook_OnRightClick)