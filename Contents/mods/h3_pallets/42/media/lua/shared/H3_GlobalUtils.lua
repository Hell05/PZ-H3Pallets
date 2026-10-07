---@diagnostic disable: undefined-global
-- ============================================================================
-- Global Utility functions used by multiple files
-- ============================================================================

local debugLogging = true  -- toggle off if you want to hide generic logging and safe warnings

local debugH3 = {}
function debugH3.log(text1, text2, text3)
    if debugLogging then print("[H3 Log]  ", tostring(text1 or "") .. tostring(text2 or "") .. tostring(text3 or "")) end
end
function debugH3.warn(text1, text2, text3)
    if debugLogging then print("[=== [H3 WARN] ===]  ", tostring(text1 or "") .. tostring(text2 or "") .. tostring(text3 or "")) end
end
function debugH3.error(text1, text2, text3) print("[!!! [H3 ERROR] !!!]  ", tostring(text1 or "") .. tostring(text2 or "") .. tostring(text3 or "")) end

-- ============================================================================

--[[ returns an item table such as e.g. below.  I use a similar data structure for the modData that gets passed as well to keep it consistent.

{                              |{
    ["Base.PropaneTank"] = {   |    ["Base.SteelIngot"] = {
        pname = "delta",       |        pname = "normal",
        ptable = {             |        ptable = {
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
            pname = "normal",
            ptable = {}
        }

        itemTable[fullType] = itemData
    end


    if instanceof(itemObj, "DrainableComboItem") then
        itemData.pname = "delta"
        local itemDelta = math.floor(itemObj:getCurrentUsesFloat() * 100 + 0.5) / 100
        itemData.ptable[itemDelta] = (itemData.ptable[itemDelta] or 0) + 1

    elseif itemObj:getConditionMax() > 10 then
        itemData.pname = "condition"
        local condition = itemObj:getCondition()
        itemData.ptable[condition] = (itemData.ptable[condition] or 0) + 1

    else
        itemData.pname = "normal"
        itemData.ptable.normal = (itemData.ptable.normal or 0) + 1
    end

    return itemTable
end

-- returns a table of available items to iterate through
function H3_GetAvailableItems(itemInput, allInventoryItems, allGroundItems)
    debugH3.log("itemInput: ", itemInput)
    if not itemInput then
        debugH3.log("missing itemInput: ", itemInput)
        return {}
    end
    local itemsTable = {}

    if type(itemInput) == "string" then
        itemsTable = {itemInput}

    elseif type(itemInput) == "table" then
        itemsTable = itemInput
    end

    local resultTable = {}
    for _, itemType in ipairs(itemsTable) do
        local itemTable = {}
        local foundItems = false

        -- check inventoryItems first
        local inventoryItems = allInventoryItems:getAllTypeRecurse(itemType)
        if inventoryItems then
            for i = 0, inventoryItems:size() - 1 do
                local item = inventoryItems:get(i)
                itemTable = GetItemProperties(item, itemTable)
                foundItems = true
            end
        end

        -- check groundItems next
        local groundItems = allGroundItems[itemType]
        if groundItems then
            for _, item in ipairs(groundItems) do
                itemTable = GetItemProperties(item, itemTable)
                foundItems = true
            end
        end

        -- We still want the context entry for the item but we use default properties to prevent
        -- items that can have condition or delta values being displayed all values at all times.
        -- Instead we use a generic entry to group them and only show values if they are available
        if not foundItems then
            resultTable[itemType] = { pname = "normal", ptable = { normal = 0 } }


        -- if an item was found however, then merge result
        else
            for itemKey, values in pairs(itemTable) do
            local existing = resultTable[itemKey]

                if not existing then
                    resultTable[itemKey] = { pname = values.pname, ptable = {}}

                    for propertyValue, count in pairs(values.ptable) do
                        resultTable[itemKey].ptable[propertyValue] = count
                    end
                else
                    existing.pname = values.pname
                    for propertyValue, count in pairs(values.ptable) do
                        existing.ptable[propertyValue] = (existing.ptable[propertyValue] or 0) + count
                    end
                end
            end
        end
    end

    return resultTable
end

return debugH3