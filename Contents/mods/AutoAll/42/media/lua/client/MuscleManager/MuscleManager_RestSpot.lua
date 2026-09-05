--[[
    [B42.20] Muscle Manager (Build 42 / SP + MP)
    ------------------------------------------------------------------
    Rests on nearby furniture (bed, couch, gym mat - anything the game
    itself considers a valid seat) instead of always sitting on the floor,
    then walks back to where training was happening for the next set.

    "Valid seat" is not a guessed sprite list: SeatingManager is the exact
    same registry ISRestAction and the vanilla right-click "Rest" option
    already use (SeatingManager.getInstance():getTilePositionCount(obj) > 0),
    so this recognizes whatever furniture the game itself would let the
    player rest on. Resting itself is queued through
    ISWorldObjectContextMenu.onRest(furniture, player) - the very same
    function "Rest" in the right-click menu calls - so pathing, seat
    orientation and animation are exactly vanilla's, not a re-derived copy
    of that math.

    One honest caveat: the game does distinguish "sitting on furniture" from
    "sitting on the ground" internally (isSittingOnFurniture(), setIsResting()),
    but the exact endurance-recovery-rate difference between them lives in
    compiled Java this mod can't decompile, so it isn't independently
    verified here - only the mechanism itself is real.
]]

MuscleManager = MuscleManager or {}
local MM = MuscleManager

if MM.restSpotLoaded then return end
MM.restSpotLoaded = true

local RETURN_DIST = 2 -- tiles; close enough to "home" that walking back is pointless

-- Idle think() ticks a queued rest is given to actually put the character on
-- the seat. Each of these is a tick where the action queue has drained and
-- nobody is sitting, so it is already evidence rather than a timer: three of
-- them is plenty.
local SIT_TRIES = 3

--- Identifies one piece of furniture across ticks without holding a
--- reference to a Java object as a table key.
local function furnitureKey(obj)
    local ok, key = pcall(function()
        local s = obj:getSquare()
        local sprite = obj:getSprite()
        return tostring(s and s:getX()) .. "," .. tostring(s and s:getY())
                .. "," .. tostring(s and s:getZ())
                .. "," .. tostring(sprite and sprite:getName())
    end)
    if ok and key then return key end
    return nil
end

--- The room a square belongs to, as a comparable id, or nil when the call
--- cannot be made.
local function roomKey(square)
    local ok, id = pcall(function() return square:getRoomIDString() end)
    if ok and id ~= nil then return tostring(id) end
    return nil
end

--- Whether the character could plausibly get to that square from where it is
--- standing, rather than only being near it in x/y.
---
--- Two rules, and the box scan alone had neither:
---
---   * same room. getRoomIDString answers the same thing for every square of
---     one room and something else outdoors, so an indoor character only
---     ever matches indoor furniture of that same room and an outdoor one
---     only matches outdoors. This is what stops a character in a barricaded
---     room being walked out of it to sit on the porch couch four tiles away.
---   * not walled off. isBlockedTo is the check vanilla foraging uses to
---     decide whether the character can reach and see a spot, and it is what
---     catches furniture on the far side of a wall inside the same room.
---
--- Both are pcall'd, and a call that cannot be made leaves the old
--- everything-in-the-box behaviour rather than rejecting every seat.
local function reachable(from, to)
    if roomKey(from) ~= roomKey(to) then return false end
    local ok, blocked = pcall(function() return from:isBlockedTo(to) end)
    if ok and blocked == true then return false end
    return true
end

--- Nearest object within reach that the game itself would offer "Rest" on -
--- beds, couches, benches, mats... whatever SeatingManager already knows
--- about - skipping anything already occupied, out of the room, walled off,
--- or already found to be unreachable this session.
local function findRestFurniture(player, blacklist)
    if not SeatingManager then return nil end
    local square = player:getSquare()
    if not square or not getCell() then return nil end
    local seating = SeatingManager.getInstance()
    local radius = MM.opt("travelRange") or 6

    local best, bestDist = nil, nil
    for dx = -radius, radius do
        for dy = -radius, radius do
            local dist = math.max(math.abs(dx), math.abs(dy))
            if not bestDist or dist < bestDist then
                local s = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                if s and reachable(square, s) then
                    local objects = s:getObjects()
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        local ok, count = pcall(function() return seating:getTilePositionCount(obj) end)
                        if ok and count and count > 0 then
                            local free = true
                            local okOcc, occupied = pcall(function() return obj:isFurnitureOccupied(player) end)
                            if okOcc then free = not occupied end
                            local key = furnitureKey(obj)
                            if free and not (blacklist and key and blacklist[key]) then
                                best, bestDist = obj, dist
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

--- Starts resting on furniture if any is in reach; returns true when it
--- queued something (the caller should not also sit on the ground itself).
function MM.tryRestOnFurniture(state)
    if not MM.opt("restOnFurniture") then return false end
    local player = state.player
    if player:isSitOnGround() or player:isSittingOnFurniture() then
        state.restTries = nil
        return true
    end

    -- A rest was already queued on a seat and the character is still not on
    -- it. onRest reports nothing back, so the only evidence available is
    -- that the action queue has drained without a sit. This used to return
    -- true unconditionally, so the same blocked seat was picked every think
    -- and the ground fallback never ran at all. Give it a few of those
    -- ticks, then drop that seat for the rest of the session.
    if state.restFurniture then
        state.restTries = (state.restTries or 0) + 1
        if state.restTries < SIT_TRIES then return true end

        state.restTries = nil
        local key = furnitureKey(state.restFurniture)
        if key then
            state.restBlacklist = state.restBlacklist or {}
            state.restBlacklist[key] = true
            MM.log("rest spot unreachable, skipping it: " .. key)
        end
        -- Cleared so the next set does not try to walk "home" from a seat
        -- the character never reached.
        state.restFurniture = nil
        return false
    end

    local furniture = findRestFurniture(player, state.restBlacklist)
    if not furniture then return false end

    state.restFurniture = furniture
    state.restTries = 0
    ISWorldObjectContextMenu.onRest(furniture, player:getPlayerNum())
    return true
end

--- Cancels a rest action still in progress (safety stop, or the character
--- has recovered enough to train again).
function MM.stopRestAction(player)
    local queue = ISTimedActionQueue.getTimedActionQueue(player)
    local action = queue and queue.queue[1]
    if action and (action.Type == "ISRestAction" or action.Type == "ISPathFindAction") and action.action then
        action.action:forceStop()
    end
end

--- Called once a set is about to start again: if the last rest happened on
--- furniture away from the training spot, walk back there first. Vanilla's
--- own ISFitnessAction:waitToStart() already handles standing back up.
function MM.returnFromRestSpot(state)
    if not state.restFurniture then return end
    state.restFurniture = nil
    state.restTries = nil
    local player = state.player
    local home = state.homeSquare
    if not home then return end
    local square = player:getSquare()
    if square and square:DistToProper(home) <= RETURN_DIST then return end
    ISTimedActionQueue.add(ISWalkToTimedAction:new(player, home))
end
