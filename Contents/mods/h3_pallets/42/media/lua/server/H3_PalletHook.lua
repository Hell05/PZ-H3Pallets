local function H3_OnObjectAdded(obj)
    if not obj then return end

    local modData = obj:getModData()
    local movableData = modData.movableData
    print("Running DA HOOK")
    print("movableData: ", movableData)
    if movableData and movableData.H3_overlaySprite then
        print("Do sprite overlay!! ", movableData.H3_overlaySprite)
        obj:setOverlaySprite(movableData.H3_overlaySprite)
        obj:transmitUpdatedSpriteToClients()
    end
end

Events.OnObjectAdded.Add(H3_OnObjectAdded)