--[[
    Auto All - water sources (Build 42 / SP + MP)
    ------------------------------------------------------------------
    What the game calls a water source, how much it holds, whether what
    is in it is actually water, and whether that water is tainted.

    Two modules need the same four answers - Auto Clean picks a sink to
    wash at, Auto Cook fills a pot before a soup - and they used to be
    one module's private locals. Everything here is a read: nothing
    queues an action and nothing changes an object.
]]

require "AutoAll/AutoAll_Core"

AutoAll = AutoAll or {}
local AA = AutoAll

if AA.waterLoaded then return end
AA.waterLoaded = true

AA.Water = AA.Water or {}
local Water = AA.Water

--- How much water an object can actually give us.
---
--- This is deliberately the same number ISWashClothing:isValid() tests
--- against, so anything reported as zero here genuinely cannot wash - no
--- point offering it. IsoObject.getFluidAmount() already resolves every
--- shape a water source comes in:
---   piped fixture, mains still on   -> 10000 (via isWaterInfinite)
---   fixture fed by another object   -> that source's own amount
---   tubs, barrels, wells, kettles   -> its FluidContainer amount
---   toilet cisterns                 -> getReserveWaterAmount()
---   rain puddles on a solid floor   -> puddle depth * 10
--- Rivers, lakes and the sea deliberately report 0 - the vanilla wash
--- actions refuse them, so we must not pretend otherwise.
function Water.amountOf(object)
    if not object or not instanceof(object, "IsoObject") then return 0 end
    local ok, amount = pcall(function() return object:getFluidAmount() end)
    if ok and type(amount) == "number" then return amount end
    return 0
end

--- True for anything that is plumbing at all - sink, toilet, bath, rain
--- collector, well - whether or not it currently holds a drop.
---
--- A dry fixture still gets a menu entry, greyed out with the reason.
--- Sinks run dry the moment the water is shut off, and an option that
--- silently disappears reads as a broken mod rather than an empty sink.
function Water.isFixture(object)
    if not object or not instanceof(object, "IsoObject") then return false end

    local ok, found = pcall(function()
        if object:hasComponent(ComponentType.FluidContainer) then return true end
        if object:getFluidContainer() ~= nil then return true end

        -- Piped fixtures advertise themselves through the sprite even when
        -- the mains are off and they hold nothing at all.
        local sprite = object:getSprite()
        local props = sprite and sprite:getProperties()
        if props and (props:has(IsoFlagType.waterPiped)
                or props:has(IsoPropertyType.WATER_AMOUNT)) then
            return true
        end
        return false
    end)

    return ok and found == true
end

--- True when what the object holds is water rather than petrol, paint or
--- wine.
---
--- amountOf() answers "is there a fluid", which is all a wash needs. A
--- pot of soup needs the stronger answer, because a barrel of petrol is
--- a perfectly good fluid source and a terrible soup. IsoObject.hasWater
--- is the base game's own test and covers every shape at once: infinite
--- mains, a fixture fed by another object, a FluidContainer whose fluids
--- are all in the Water category, a toilet's reserve, and the sprite
--- flags a natural source carries.
function Water.hasWater(object)
    if not object or not instanceof(object, "IsoObject") then return false end
    local ok, found = pcall(function() return object:hasWater() end)
    return ok and found == true
end

--- True when the water in this source is the tainted kind.
---
--- A test that throws is treated as tainted, because that is the
--- harmless direction: a caller that refuses tainted water refuses one
--- source too many rather than serving one bad meal.
function Water.isTainted(object)
    if not object or not instanceof(object, "IsoObject") then return false end
    local ok, tainted = pcall(function() return object:isTaintedWater() end)
    if not ok then return true end
    return tainted == true
end
