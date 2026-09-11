-- Clothing.addPatch returns early after a full restore, before its equipped
-- clothing sync. Refresh the repaired garment after vanilla completion.
if not isServer() then return end

require "TimedActions/ISRepairClothing"

local unpackValues = table.unpack or unpack
local installed = false

local function pack(...)
    return { n = select("#", ...), ... }
end

local function captureRepair(action)
    if action == nil then return nil end

    local character = action.character
    local clothing = action.clothing
    local part = action.part
    if character == nil or clothing == nil or part == nil then return nil end
    if not instanceof(character, "IsoPlayer") then return nil end
    if not character:isEquippedClothing(clothing) then return nil end

    local visual = clothing:getVisual()
    local hole = visual and visual:getHole(part)
    if hole == nil or hole <= 0 then return nil end

    return {
        action = action,
        character = character,
        clothing = clothing,
        part = part,
    }
end

local function stillNeedsSync(repair)
    if repair.action.character ~= repair.character then return false end
    if repair.action.clothing ~= repair.clothing then return false end
    if not repair.character:isEquippedClothing(repair.clothing) then return false end

    local visual = repair.clothing:getVisual()
    if visual == nil or visual:getHole(repair.part) ~= 0 then return false end
    return repair.clothing:getPatchType(repair.part) == nil
end

local function install()
    if installed then return end
    if ISRepairClothing == nil or type(ISRepairClothing.complete) ~= "function" then return end

    local originalComplete = ISRepairClothing.complete
    ISRepairClothing.complete = function(self, ...)
        local capturedOk, repair = pcall(captureRepair, self)
        if not capturedOk then repair = nil end

        local results = pack(originalComplete(self, ...))
        if results[1] == true and repair ~= nil then
            local checkOk, needsSync = pcall(stillNeedsSync, repair)
            if checkOk and needsSync then
                syncVisuals(repair.character)
                syncClothingFields(repair.character)
            end
        end
        return unpackValues(results, 1, results.n)
    end
    installed = true
    print("[AutoAll] worn-clothing repair sync installed")
end

Events.OnServerStarted.Add(install)
