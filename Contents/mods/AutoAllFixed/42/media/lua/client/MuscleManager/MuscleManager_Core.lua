--[[
    [B42.20] Muscle Manager (Build 42 / SP + MP)
    ------------------------------------------------------------------
    The exercise / rest / repeat loop.

    The mod never simulates the exercise: it queues the vanilla
    ISFitnessAction, watches endurance and stops/restarts it. That is why
    XP, stiffness, calories and animations behave exactly like the base
    game, and why it runs on a multiplayer server with no server-side
    file (in vanilla the fitness action is already a net action, driven by
    the server through animation events).
]]

MuscleManager = MuscleManager or {}
local MM = MuscleManager

if MM.coreLoaded then return end
MM.coreLoaded = true

MM.states = MM.states or {}     -- [playerNum] = state

local MP             = isClient()   -- true on a multiplayer client
local THINK_INTERVAL = 350          -- ms between two decisions
local START_GRACE    = 1500         -- ms of "manual input" ignored after a set starts
local TREAT_COOLDOWN = 60000        -- ms between two pain treatments
local EAT_COOLDOWN   = 20000        -- ms between two meals
local BORROW_COOLDOWN = 8000        -- ms between two attempts to fetch an item
local START_TIMEOUT  = MP and 6000 or 2500  -- ms allowed for a set to actually start
local MAX_FAILED     = 3            -- give up after this many sets that never started

---------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------

local function now()
    return getTimestampMs()
end

--- Goes to console.txt / the Logs folder, so a session can be diagnosed later.
function MM.log(msg)
    print("[MuscleManager] " .. tostring(msg))
end

local function currentAction(player)
    local queue = ISTimedActionQueue.getTimedActionQueue(player)
    return queue and queue.queue[1] or nil
end

--- Endurance as 0..1 (1 = fully rested).
function MM.getEndurance(player)
    local stats = player:getStats()
    local ok, value = pcall(function() return stats:get(CharacterStat.ENDURANCE) end)
    if ok and type(value) == "number" then return value end
    return 1
end

--- Intoxication as 0..100.
function MM.getDrunkenness(player)
    local stats = player:getStats()
    local ok, value = pcall(function() return stats:get(CharacterStat.INTOXICATION) end)
    if ok and type(value) == "number" then return value end
    return 0
end

function MM.isRunning(player)
    local state = MM.states[player:getPlayerNum()]
    return state ~= nil and state.active == true
end

function MM.getState(player)
    return MM.states[player:getPlayerNum()]
end

--- True when the character is too tired for the vanilla action to even start.
function MM.isTooTired(player)
    return player:getMoodles():getMoodleLevel(MoodleType.ENDURANCE) > ISFitnessUI.enduranceLevelThreshold
end

---------------------------------------------------------------------
-- messages
---------------------------------------------------------------------

function MM.say(state, text, bad)
    local mode = MM.opt("notify")
    if mode == 3 or not text then return end

    -- Say() only draws a chat bubble, it does not emit a world sound, so it
    -- will not attract zombies.
    if mode == 2 then
        state.player:Say(text)
        return
    end

    -- Same overloads the base game uses for halo text.
    local ok = pcall(function()
        if bad then
            HaloTextHelper.addBadText(state.player, text)
        else
            HaloTextHelper.addGoodText(state.player, text, "[br/]")
        end
    end)
    if not ok then
        state.player:Say(text)
    end
end

--- Same message is only repeated every "notifyEvery" seconds.
function MM.reason(state, text)
    local every = (MM.opt("notifyEvery") or 20) * 1000
    if state.lastReason == text and now() - (state.lastReasonAt or 0) < every then return end
    state.lastReason = text
    state.lastReasonAt = now()
    MM.say(state, text, false)
end

---------------------------------------------------------------------
-- game speed (single player only - the server owns game speed in MP)
---------------------------------------------------------------------

-- setGameSpeed() alone only moves the topbar icon: the calendar actually
-- speeds up through getGameTime():setMultiplier(). These pairs mirror what
-- SpeedControlsHandler.lua uses for the vanilla Fast Forward x1/x2/x3 keys,
-- so our "2x / 3x / Very fast" behave exactly like the real hotkeys instead
-- of a made-up scale.
local SPEEDS = { 1, 2, 3, 4 }
local MULTS  = { 1, 5, 20, 40 }

local function canChangeSpeed()
    return not isClient() and not isServer()
end

local function currentSpeedSlot()
    local ok, slot = pcall(function()
        local controls = UIManager.getSpeedControls()
        if controls then return controls:getCurrentGameSpeed() end
        return getGameSpeed()
    end)
    if ok and type(slot) == "number" then return slot end
    return nil
end

local function setRealSpeed(index)
    pcall(function()
        local controls = UIManager.getSpeedControls()
        if controls then
            controls:SetCurrentGameSpeed(SPEEDS[index] or 1)
        else
            setGameSpeed(SPEEDS[index] or 1)
        end
        getGameTime():setMultiplier(MULTS[index] or 1)
    end)
end

-- ISTimedActionQueue.lua resets the game speed to 1 whenever the action
-- queue goes idle and the vanilla "reset game speed when a timed action
-- ends" option is on, which is between every single set. Re-asserting the
-- speed on every tick used to paper over that, and it is exactly what made
-- pausing impossible. With a latch in place that reset would instead read as
-- the player choosing 1x and stand the session down, so the flag is cleared
-- while a session owns the speed. Same fix, same reason, as holdGameSpeed in
-- AutoAll_Core.
local function releaseVanillaReset()
    if ISTimedActionQueue then
        ISTimedActionQueue.shouldResetGameSpeed = false
    end
end

--- Takes the game speed up once, then leaves the player alone.
---
--- This used to write the configured speed back on every tick whenever the
--- current slot differed, so a pause or a manual 1x was undone before it
--- reached the screen. It is now the same latch AutoAll_Core uses
--- (AA.applySpeed): the slot we set is remembered, and the first slot we did
--- not set stands the session down for good. Pause is slot 0 and is a player
--- choice like any other.
function MM.applySpeed(state)
    if not canChangeSpeed() then return end
    if state.speedGaveUp then return end

    local index = MM.opt("fastForward") or 1
    if index <= 1 then return end
    local wanted = SPEEDS[index]
    if not wanted then return end

    local slot = currentSpeedSlot()
    if slot == nil then return end

    if state.speedHeld then
        -- Still the slot we set? If not, the player moved it. Hands off for
        -- the rest of the session.
        if slot ~= wanted then
            state.speedHeld   = false
            state.speedGaveUp = true
            state.speedFollow = true
        end
        return
    end

    -- Only ever taken from a standing start. Anything else is the player's
    -- own choice: a faster speed they picked, or a pause we must not undo.
    if slot ~= 1 then
        state.speedGaveUp = true
        -- Their speed, not ours, so it is never written to. Vanilla's reset
        -- would still knock it back after the next set, which reads as the
        -- mod refusing to let them speed the game up, so it stays defended
        -- for the length of the session.
        state.speedFollow = true
        return
    end

    setRealSpeed(index)
    state.speedHeld = true
    releaseVanillaReset()
end

function MM.releaseSpeed(state)
    if not canChangeSpeed() then return end
    if not state.speedHeld then return end
    state.speedHeld = false
    setRealSpeed(1)
end

-- The base game resets speed to 1 on its own: ISTimedActionQueue.onTick does
-- it whenever the character briefly isn't "doing an action" (standing up,
-- switching sets...) and the "resume normal speed" option is on, and
-- ISFitnessAction.stop()/perform() do it on every single set. Both run every
-- tick, which is why the vanilla reset is disarmed here rather than fought
-- with a re-assert: a re-assert cannot tell a reset apart from the player,
-- and that is what made the speed impossible to change by hand.
local function speedTick()
    -- The Auto All switch, same as onPlayerUpdate. A loop that is not
    -- allowed to run must not be holding the game speed up either.
    if not MM.enabled() then return end
    if not canChangeSpeed() then return end
    for _, state in pairs(MM.states) do
        if state.active then
            -- speedHeld   = a speed this session set and still owns
            -- speedFollow = a speed the player set, which is not written to
            --               but is defended for the length of the session
            if state.speedHeld or state.speedFollow then
                releaseVanillaReset()
            end
            if state.phase == "exercising" or MM.opt("holdSpeed") then
                MM.applySpeed(state)
            end
        end
    end
end
Events.OnTick.Add(speedTick)

---------------------------------------------------------------------
-- exercise rotation
---------------------------------------------------------------------

-- Vanilla order; anything added by another mod is appended after these.
local BASE_ORDER = { "squats", "pushups", "situp", "burpees", "barbellcurl", "dumbbellpress", "bicepscurl" }

--- Exercises the character can actually do right now (equipment in the bag,
--- or - for FWO's treadmill/bench press - the machine within reach).
function MM.availableExercises(player)
    local seen, list = {}, {}
    local function tryAdd(key, data)
        if not data or seen[key] then return end

        -- FWO registers 5 ids per machine (base + one per facing); they all
        -- collapse into a single rotation entry, offered only when the
        -- equipment is actually reachable right now.
        local furnitureBase = MM.furnitureBaseType(key)
        if furnitureBase then
            if seen[furnitureBase] then return end
            if not MM.canUseFurnitureExercise(furnitureBase, player) then return end
            seen[furnitureBase] = true
            list[#list + 1] = furnitureBase
            return
        end

        if data.item and not player:getInventory():contains(data.item, true) then return end
        seen[key] = true
        list[#list + 1] = key
    end
    for _, key in ipairs(BASE_ORDER) do
        tryAdd(key, FitnessExercises.exercisesType[key])
    end
    for key, data in pairs(FitnessExercises.exercisesType) do
        tryAdd(key, data)
    end
    return list
end

--- Next exercise in the rotation, wrapping around.
function MM.nextExercise(state)
    local list = MM.availableExercises(state.player)
    if #list == 0 then return state.exercise end
    local index = 0
    for i, key in ipairs(list) do
        if key == state.exercise then
            index = i
            break
        end
    end
    return list[(index % #list) + 1]
end

---------------------------------------------------------------------
-- start / stop
---------------------------------------------------------------------

---------------------------------------------------------------------
-- the Auto All task slot
--
-- The exercise loop keeps its own OnPlayerUpdate think(). It is a different
-- shape from every other automation and replacing it would be a rewrite
-- rather than a fix. What it did not have was a seat at Auto All's table:
-- ESC stopped every job except this one, AA.isRunning could not see a
-- session at all, and starting Auto Cook queued a second job into the same
-- action queue, whose stop then cleared the fitness set out from under it.
--
-- A shim task fixes all three without touching the loop. It registers
-- through AA.startTask, so the one-task-at-a-time rule and AA.checkSafety
-- apply to a training session like they do to everything else. Its think()
-- does nothing, it never clears the action queue (the loop owns that), and
-- its onStop ends the session with a message. Auto All's own speed latch is
-- stood down from the start, because MM.applySpeed already owns the speed
-- here and two latches writing the same slot would each read the other as
-- the player.
---------------------------------------------------------------------

--- Claims Auto All's single task slot for this session. Does nothing at all
--- when the loop is running standalone and there is no Auto All to ask.
function MM.claimTaskSlot(state)
    if not (AutoAll and type(AutoAll.startTask) == "function") then return end
    local player = state.player

    local task = {
        player           = player,
        kind             = "exercise",
        -- The loop manages its own queue: rests, meals and returns are all
        -- queued by think() and clearing them on stop would cancel the very
        -- cleanup the stop is for.
        clearQueueOnStop = false,
        -- It walks to rest spots and gym machines on its own, so "the
        -- character is moving" is not the player taking over.
        allowMove        = true,
        speedGaveUp      = true,
        think            = function() end,
        onStop           = function()
            state.aaTask = nil
            -- A no-op when the stop started in MM.stop. The real work when
            -- Auto All stopped us: ESC, or another job taking the slot.
            MM.stop(player, getText("UI_MM_stop_generic"), false)
            -- Last, so the transfers sit behind the forceStops MM.stop does.
            MM.returnAllBorrowed(state)
        end,
    }

    state.aaTask = task
    pcall(AutoAll.startTask, task)
end

--- Hands the slot back. AA.stop runs our onStop, which is where the session
--- and the borrowed items are wound up.
function MM.releaseTaskSlot(state)
    local task = state.aaTask
    if not task then return end
    if not (AutoAll and type(AutoAll.stop) == "function") then
        state.aaTask = nil
        return
    end
    -- Only when it is still ours. Auto All may already have replaced it, in
    -- which case onStop has run and there is nothing left to release.
    if AutoAll.tasks and AutoAll.tasks[task.playerNum] ~= task then
        state.aaTask = nil
        return
    end
    pcall(AutoAll.stop, state.player, nil, false)
end

--- Cancels the running vanilla fitness action, if any (same as the panel's Cancel button).
function MM.stopFitnessAction(player)
    local action = currentAction(player)
    if action and action.Type == "ISFitnessAction" then
        player:setVariable("ExerciseStarted", false)
        if action.action then
            action.action:forceStop()
        end
    end
end

--- Shows the on-screen session card (sets, time, XP gained) if the session
--- actually trained at least one set. Skipped on death - not the moment for it.
function MM.showSummary(state)
    if not MM.opt("showSummary") then return end
    if (state.sets or 0) <= 0 then return end
    local player = state.player
    if player:isDead() then return end
    if not (state.xpStartStrength and state.sessionStartAt) then return end

    local xp = player:getXp()
    local xpStrength = math.max(0, xp:getXP(Perks.Strength) - state.xpStartStrength)
    local xpFitness = math.max(0, xp:getXP(Perks.Fitness) - state.xpStartFitness)
    local levelStrength = player:getPerkLevel(Perks.Strength)
    local levelFitness = player:getPerkLevel(Perks.Fitness)

    MuscleManagerSummaryUI.show({
        sets = state.sets,
        elapsedMs = now() - state.sessionStartAt,
        xpStrength = xpStrength,
        xpFitness = xpFitness,
        levelStrength = levelStrength,
        levelFitness = levelFitness,
        leveledStrength = levelStrength > state.levelStartStrength,
        leveledFitness = levelFitness > state.levelStartFitness,
    })
end

function MM.stop(player, reason, bad)
    local state = MM.states[player:getPlayerNum()]
    if not state then return end
    MM.states[player:getPlayerNum()] = nil
    state.active = false
    MM.log("stop after " .. tostring(state.sets) .. " sets: " .. tostring(reason))
    MM.releaseSpeed(state)
    MM.stopFitnessAction(player)
    MM.stopRestAction(player)
    -- Hands Auto All's slot back. Its onStop returns the borrowed items, so
    -- the call below only does anything when there is no Auto All to hand
    -- the slot back to.
    MM.releaseTaskSlot(state)
    -- After the forceStops above, so the transfers are not the thing being
    -- cancelled. A stop used to keep whatever was borrowed.
    MM.returnAllBorrowed(state)
    MM.showSummary(state)
    if reason then
        MM.say(state, reason, bad ~= false)
    end
end

function MM.start(player, exercise, minutes, panel)
    -- A directional FWO id (e.g. "treadmill_n") picked straight off the
    -- panel is normalized to its base type; MM.beginSet resolves the real
    -- direction fresh from whatever machine is actually found each time.
    local furnitureBase = MM.furnitureBaseType(exercise)
    if furnitureBase then
        exercise = furnitureBase
    end

    local exeData = FitnessExercises and FitnessExercises.exercisesType[exercise]
    if not exeData then return false end

    local xp = player:getXp()
    local state = {
        player       = player,
        exercise     = exercise,
        exeData      = exeData,
        minutes      = minutes or MM.opt("setMinutes"),
        panel        = panel,
        active       = true,
        phase        = "exercising",
        sets         = 0,
        failedStarts = 0,
        lastHealth   = player:getBodyDamage():getOverallBodyHealth(),
        nextThink    = 0,
        homeSquare   = player:getSquare(),
        sessionStartAt     = now(),
        xpStartStrength    = xp:getXP(Perks.Strength),
        xpStartFitness     = xp:getXP(Perks.Fitness),
        levelStartStrength = player:getPerkLevel(Perks.Strength),
        levelStartFitness  = player:getPerkLevel(Perks.Fitness),
    }
    -- Claimed before the state is installed: if a stale exercise task is
    -- still holding the slot, AA.startTask stops it, and that stop has to
    -- find the old session rather than this one.
    MM.claimTaskSlot(state)
    MM.states[player:getPlayerNum()] = state

    MM.log("start " .. tostring(exercise) .. " / " .. tostring(state.minutes) .. " min / endurance "
            .. math.floor(MM.getEndurance(player) * 100))
    MM.say(state, getText("UI_MM_started", exeData.name), false)

    -- Starting already exhausted would make the vanilla action refuse to
    -- start (ISFitnessAction:isValidStart), so rest first in that case.
    if MM.isTooTired(player) or MM.getEndurance(player) * 100 < MM.opt("resumeAt") then
        MM.beginRest(state)
    else
        MM.beginSet(state)
    end
    return true
end

---------------------------------------------------------------------
-- phases
---------------------------------------------------------------------

function MM.beginSet(state)
    local player = state.player

    -- One exercise per set when rotation is on (the first set keeps the one
    -- picked on the panel).
    if MM.opt("rotate") and state.sets > 0 then
        local nextKey = MM.nextExercise(state)
        local nextData = nextKey and FitnessExercises.exercisesType[nextKey]
        if nextData then
            state.exercise = nextKey
            state.exeData = nextData
        end
    end

    -- FWO's treadmill/bench press: no vanilla item to equip, the character
    -- has to walk to the actual machine instead. Delegates the whole
    -- walk/face/equip/queue sequence to FWO's own handler (see
    -- MuscleManager_FWOCompat.lua) rather than starting in place.
    local furnitureBase = MM.furnitureBaseType(state.exercise)
    if furnitureBase then
        -- FWO's own walk-to-machine already starts from wherever the
        -- character currently is, so there is nothing to "return" from.
        state.restFurniture = nil
        if not MM.startFurnitureExercise(state, furnitureBase) then
            MM.stop(player, getText("UI_MM_stop_noitem"), true)
            return
        end
    else
        -- Came back from resting on furniture away from the training spot:
        -- walk home first instead of just starting the next set on the couch.
        MM.returnFromRestSpot(state)

        if state.exeData.item and not player:getInventory():contains(state.exeData.item, true) then
            MM.stop(player, getText("UI_MM_stop_noitem"), true)
            return
        end

        -- Vanilla equip/unequip logic: it only reads .player and .exeData, so it
        -- can be called without an open panel.
        if not ISFitnessUI.equipItems({ player = player, exeData = state.exeData }) then
            MM.stop(player, getText("UI_MM_stop_noitem"), true)
            return
        end

        local action = ISFitnessAction:new(player, state.exercise, state.minutes, state.exeData, state.exeData.type)
        action.fitnessUI = state.panel
        ISTimedActionQueue.addGetUpAndThen(player, action)
    end

    state.phase = "exercising"
    state.sawAction = false
    state.setStartedAt = now()
    state.sets = state.sets + 1
    MM.applySpeed(state)
    MM.log("set " .. state.sets .. " queued")
end

function MM.sitDownToRest(state)
    local player = state.player
    if player:isSitOnGround() or player:isSittingOnFurniture() then return end
    if currentAction(player) then return end
    if player:getVehicle() or player:isClimbing() then return end

    -- Prefer a nearby bed/couch/mat over the floor; falls back below if none
    -- is in reach or the option is off.
    if MM.tryRestOnFurniture(state) then return end

    if not MM.opt("sitToRest") then return end
    player:setAutoWalk(false)
    player:reportEvent("EventSitOnGround")
end

function MM.beginRest(state)
    state.phase = "resting"
    state.restStartedAt = now()
    MM.log("resting at endurance " .. math.floor(MM.getEndurance(state.player) * 100))
    if MM.opt("holdSpeed") then
        MM.applySpeed(state)
    else
        MM.releaseSpeed(state)
    end
    MM.reason(state, getText("UI_MM_resting"))
    MM.sitDownToRest(state)
end

---------------------------------------------------------------------
-- finding items around the character
---------------------------------------------------------------------

local MAX_BAG_DEPTH = 2     -- bag inside a bag, no deeper

--- Looks for a matching item inside one container (and inside bags in it).
local function scanContainer(container, predicate, depth)
    if not container then return nil end
    local items = container:getItems()
    if not items then return nil end
    local bags
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if predicate(item) then
            return item, container
        end
        if depth < MAX_BAG_DEPTH and instanceof(item, "InventoryContainer") then
            bags = bags or {}
            bags[#bags + 1] = item
        end
    end
    for _, bag in ipairs(bags or {}) do
        local found, from = scanContainer(bag:getInventory(), predicate, depth + 1)
        if found then return found, from end
    end
    return nil
end

--- Searches the player inventory first, then - if allowed - the floor and the
--- containers (bags, crates, counters...) within range.
--- Returns item, container, worldObject. A nil container means "already ours".
function MM.findItem(player, predicate)
    local item = player:getInventory():getFirstEvalRecurse(predicate)
    if item then return item, nil, nil end
    if not MM.opt("useNearby") then return nil end

    local square = player:getSquare()
    local cell = getCell()
    if not square or not cell then return nil end

    local range = MM.opt("nearbyRange") or 3
    local best, bestContainer, bestWorld, bestDist = nil, nil, nil, nil

    for dx = -range, range do
        for dy = -range, range do
            local dist = math.max(math.abs(dx), math.abs(dy))
            if bestDist == nil or dist < bestDist then
                local s = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                if s then
                    -- loose items lying on the ground
                    local world = s:getWorldObjects()
                    for i = 0, world:size() - 1 do
                        local worldObject = world:get(i)
                        local worldItem = worldObject:getItem()
                        if worldItem then
                            if predicate(worldItem) then
                                best, bestContainer, bestWorld, bestDist =
                                    worldItem, worldItem:getContainer(), worldObject, dist
                                break
                            end
                            if instanceof(worldItem, "InventoryContainer") then
                                -- a bag dropped on the floor
                                local found, from = scanContainer(worldItem:getInventory(), predicate, 1)
                                if found then
                                    best, bestContainer, bestWorld, bestDist = found, from, nil, dist
                                    break
                                end
                            end
                        end
                    end

                    -- containers of furniture, crates, counters...
                    if bestDist ~= dist then
                        local objects = s:getObjects()
                        for i = 0, objects:size() - 1 do
                            local found, from = scanContainer(objects:get(i):getContainer(), predicate, 1)
                            if found then
                                best, bestContainer, bestWorld, bestDist = found, from, nil, dist
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    return best, bestContainer, bestWorld
end

--- Brings a borrowed item over (walking there if needed) and remembers where
--- it came from, so the leftovers can go back.
---
--- A list, not a single slot. Borrowing pills and then food used to overwrite
--- the pills entry, and the pills stayed in the bag for good.
function MM.borrow(state, item, container, worldObject)
    if not container then return end
    state.borrowed = state.borrowed or {}
    state.borrowed[#state.borrowed + 1] = {
        item = item,
        container = container,
        fromFloor = worldObject ~= nil or container:getType() == "floor",
    }
    ISInventoryPaneContextMenu.transferIfNeeded(state.player, worldObject or item)
    MM.log("borrowing " .. tostring(item:getType()) .. " from " .. tostring(container:getType()))
end

--- Queues one borrowed item back where it came from.
--- Returns true when a transfer was actually queued.
function MM.queueReturn(state, borrowed)
    if not borrowed then return false end
    if not MM.opt("putItemBack") then return false end

    local player = state.player
    local item = borrowed.item
    -- Fully consumed items simply stopped existing: nothing to give back.
    if not item or not player:getInventory():contains(item) then return false end

    local destination = borrowed.container
    if borrowed.fromFloor then
        destination = ISInventoryPage.GetFloorContainer(player:getPlayerNum())
    end
    if not destination or destination == player:getInventory() then return false end

    ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(
            player, item, player:getInventory(), destination))
    MM.log("returning " .. tostring(item:getType()))
    return true
end

--- Puts what is left of the oldest borrowed item back where it came from.
--- Returns true when an action was queued, so the rest phase waits for it.
function MM.returnBorrowed(state)
    local list = state.borrowed
    if not list or #list == 0 then return false end
    if currentAction(state.player) then return false end

    -- Entries that have nothing left to give back are dropped rather than
    -- queued, so one eaten sandwich does not stall the list behind it.
    while #list > 0 do
        if MM.queueReturn(state, table.remove(list, 1)) then return true end
    end
    return false
end

--- Every borrowed item goes back at the end of a session, not just whichever
--- one happened to be current. Called from the stop path, where there is no
--- next think() to work through the list one at a time.
function MM.returnAllBorrowed(state)
    local list = state.borrowed
    if not list then return end
    state.borrowed = nil
    for _, borrowed in ipairs(list) do
        MM.queueReturn(state, borrowed)
    end
end

---------------------------------------------------------------------
-- pain
---------------------------------------------------------------------

local function hasUsesLeft(item)
    return item:getCurrentUsesFloat() > 0
end

local function isAlcoholicDrink(item)
    local container = item:getFluidContainer()
    if not container or container:isEmpty() then return false end
    local fluid = container:getPrimaryFluid()
    if not fluid then return false end
    local ok, result = pcall(function() return fluid:isCategory(FluidCategory.Alcoholic) end)
    return ok and result == true
end

local function isPainkiller(item)
    return item:getFullType() == "Base.Pills" and hasUsesLeft(item)
end

--- True when the item is ours to use right now; otherwise it fetches it and
--- the next tick uses it from the inventory.
local function reachFor(state, item, container, worldObject)
    if not item then return false end
    if not container then return true end
    if now() - (state.lastBorrowAt or 0) < BORROW_COOLDOWN then return false end
    state.lastBorrowAt = now()
    MM.borrow(state, item, container, worldObject)
    return false
end

--- Returns true when a treatment action was queued.
function MM.tryTreatPain(state)
    local player = state.player
    if not MM.opt("treatPain") then return false end
    if player:getMoodles():getMoodleLevel(MoodleType.PAIN) < MM.opt("painLevel") then return false end
    if now() - (state.lastTreatAt or 0) < TREAT_COOLDOWN then return false end
    if currentAction(player) then return false end

    if MM.opt("usePills") then
        local pills, container, worldObject = MM.findItem(player, isPainkiller)
        if pills then
            if not reachFor(state, pills, container, worldObject) then return true end
            state.lastTreatAt = now()
            ISTimedActionQueue.add(ISTakePillAction:new(player, pills))
            MM.say(state, getText("UI_MM_takingPills"), false)
            return true
        end
    end

    if MM.opt("useBooze") and MM.getDrunkenness(player) < MM.opt("maxDrunk") then
        local bottle, container, worldObject = MM.findItem(player, isAlcoholicDrink)
        if bottle then
            if not reachFor(state, bottle, container, worldObject) then return true end
            state.lastTreatAt = now()
            local sip = (MM.opt("boozeSip") or 5) / 100
            ISTimedActionQueue.add(ISDrinkFluidAction:new(player, bottle, sip))
            MM.say(state, getText("UI_MM_takingBooze"), false)
            return true
        end
    end

    return false
end

---------------------------------------------------------------------
-- food
---------------------------------------------------------------------

--- Safe to eat right now: no rot, no poison, no raw meat, and it actually
--- feeds (cigarettes and spices have no hunger value).
local function isEdible(item)
    if not instanceof(item, "Food") then return false end
    if item:isRotten() or item:isSpice() or item:isFrozen() then return false end
    if item:isPoison() then return false end
    if item:isbDangerousUncooked() and not item:isCooked() and not item:isBurnt() then return false end
    if item:hasTag(ItemTag.SMOKABLE) then return false end
    return item:getHungerChange() < 0
end

--- Hunger as 0..1 (1 = starving).
function MM.getHunger(player)
    local stats = player:getStats()
    local ok, value = pcall(function() return stats:get(CharacterStat.HUNGER) end)
    if ok and type(value) == "number" then return value end
    return 0
end

--- Returns true when an eat action was queued.
function MM.tryEat(state)
    local player = state.player
    if not MM.opt("autoEat") then return false end
    if player:getMoodles():getMoodleLevel(MoodleType.HUNGRY) < MM.opt("eatAt") then return false end
    -- Same gate as the vanilla eat action: a stuffed character refuses to eat.
    if player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3 then return false end
    if now() - (state.lastEatAt or 0) < EAT_COOLDOWN then return false end
    if currentAction(player) then return false end

    local food, container, worldObject = MM.findItem(player, isEdible)
    if not food then
        MM.reason(state, getText("UI_MM_noFood"))
        return false
    end
    if not reachFor(state, food, container, worldObject) then return true end

    -- Eat only what the hunger bar can take, so a big meal is not wasted.
    local percentage = 1
    local change = math.abs(food:getHungerChange())
    if change > 0 then
        percentage = math.min(1, math.max(0.25, MM.getHunger(player) / change))
        percentage = math.ceil(percentage * 4) / 4
    end

    state.lastEatAt = now()
    ISTimedActionQueue.add(ISEatFoodAction:new(player, food, percentage))
    MM.log("eating " .. tostring(food:getType()) .. " at " .. tostring(percentage))
    MM.say(state, getText("UI_MM_eating", food:getName()), false)
    return true
end

---------------------------------------------------------------------
-- safety
---------------------------------------------------------------------

--- A stop condition is on when Muscle Manager's own option says so, or when
--- Auto All's matching one does.
---
--- Auto Exercise is one of Auto All's modules, so a player who ticked "stop
--- when zombies are near" over there expects it to hold here too. The two
--- panels carry the same key for the same idea and neither is going to be
--- kept in step with the other by hand, so either one arms the stop.
local function stopOptionOn(key)
    if MM.opt(key) then return true end
    if AutoAll and type(AutoAll.opt) == "function" then
        local ok, value = pcall(AutoAll.opt, key)
        if ok and value == true then return true end
    end
    return false
end

--- A fracture, an untreated deep wound or active bleeding: reasons to stop
--- that overall body health never shows.
---
--- The health check below is a per-think delta, and these hurt far too
--- slowly to move it - a slow bleed and a broken arm both read as a
--- perfectly healthy character right up until they do not. Training on any
--- of them makes them worse.
local function injuredBodyPart(player)
    local ok, hurt = pcall(function()
        local parts = player:getBodyDamage():getBodyParts()
        if not parts then return false end
        for i = 0, parts:size() - 1 do
            local part = parts:get(i)
            if part then
                if part:getFractureTime() > 0 then return true end
                if part:isDeepWounded() then return true end
                if part:getBleedingTime() > 0 then return true end
            end
        end
        return false
    end)
    return ok and hurt == true
end

--- Returns a message when auto mode must end, nil otherwise.
function MM.checkSafety(state)
    local player = state.player

    if player:isDead() then return getText("UI_MM_stop_generic") end
    if player:getVehicle() then return getText("UI_MM_stop_vehicle") end

    if stopOptionOn("stopZombie") then
        local stats = player:getStats()
        if stats:getNumVisibleZombies() > 0 or stats:getNumChasingZombies() > 0
                or stats:getNumVeryCloseZombies() > 0 then
            return getText("UI_MM_stop_zombie")
        end
    end

    local health = player:getBodyDamage():getOverallBodyHealth()
    local damaged = health < (state.lastHealth or health) - 0.05
    state.lastHealth = health
    if stopOptionOn("stopDamage") and damaged then
        return getText("UI_MM_stop_damage")
    end
    if MM.opt("stopLowHealth") and health < MM.opt("minHealth") then
        return getText("UI_MM_stop_health")
    end

    if injuredBodyPart(player) then
        return getText("UI_MM_stop_injury")
    end

    if MM.opt("stopHeavyLoad") and player:getMoodles():getMoodleLevel(MoodleType.HEAVY_LOAD) > 2 then
        return getText("UI_MM_stop_load")
    end

    if MM.opt("stopManual") and now() - (state.setStartedAt or 0) > START_GRACE then
        if player:pressedMovement(true) or player:isAiming() then
            return getText("UI_MM_stop_manual")
        end
    end

    if MM.opt("stopOnClose") and state.panel and not state.panel:getIsVisible() then
        return getText("UI_MM_stop_panel")
    end

    -- ESC. The Auto All task slot covers AA.stopAll, but the per-tick cancel
    -- press is what every other automation checks for itself and it has to
    -- work here whether or not the slot was ever claimed. Same grace window
    -- as the manual-control check, so the ESC that closed a menu just before
    -- the set started does not end it.
    if now() - (state.setStartedAt or 0) > START_GRACE then
        local ok, cancelled = pcall(function() return player:pressedCancelAction() end)
        if ok and cancelled == true then
            return getText("UI_MM_stop_manual")
        end
    end

    return nil
end

---------------------------------------------------------------------
-- main loop
---------------------------------------------------------------------

function MM.think(state)
    local player = state.player

    local stopReason = MM.checkSafety(state)
    if stopReason then
        MM.stop(player, stopReason, true)
        return
    end

    local action = currentAction(player)
    local exercising = action ~= nil and action.Type == "ISFitnessAction"
    local endurance = MM.getEndurance(player) * 100
    local restAt = MM.opt("restAt")
    local resumeAt = MM.opt("resumeAt")
    local maxSets = MM.opt("maxSets") or 0

    if state.phase == "exercising" then
        if exercising then
            state.sawAction = true
            state.failedStarts = 0
            if endurance <= restAt then
                MM.stopFitnessAction(player)
                MM.beginRest(state)
            end
            return
        end

        -- Getting up, unequipping a bag, walking to the spot: let the queue finish.
        if action ~= nil then return end

        if not state.sawAction then
            if now() - (state.setStartedAt or 0) < START_TIMEOUT then return end
            state.failedStarts = state.failedStarts + 1
            if state.failedStarts >= MAX_FAILED then
                MM.stop(player, getText("UI_MM_stop_cantstart"), true)
                return
            end
        end

        -- Set is over (time is up, or vanilla stopped it because of endurance).
        if maxSets > 0 and state.sets >= maxSets and state.sawAction then
            MM.stop(player, getText("UI_MM_stop_sets", state.sets), false)
            return
        end

        if endurance >= resumeAt and not MM.isTooTired(player)
                and player:getMoodles():getMoodleLevel(MoodleType.PAIN) <= 3 then
            MM.beginSet(state)
        else
            MM.beginRest(state)
        end
        return
    end

    if state.phase == "resting" then
        if MM.returnBorrowed(state) then return end
        if MM.tryTreatPain(state) then return end
        if MM.tryEat(state) then return end

        -- A furniture rest action runs on its own until 100% endurance -
        -- interrupt it ourselves once our own resumeAt threshold is met,
        -- otherwise that option would be ignored whenever furniture is used.
        if state.restFurniture and action and action.Type == "ISRestAction"
                and endurance >= resumeAt and not MM.isTooTired(player)
                and player:getMoodles():getMoodleLevel(MoodleType.PAIN) <= 3 then
            MM.stopRestAction(player)
            return
        end

        if action ~= nil then return end        -- swallowing pills / eating / walking to the seat / standing up

        if player:getMoodles():getMoodleLevel(MoodleType.PAIN) > 3 then
            MM.reason(state, getText("UI_MM_wait_pain"))
            MM.sitDownToRest(state)
            return
        end

        if endurance < resumeAt or MM.isTooTired(player) then
            MM.reason(state, getText("UI_MM_wait_endurance"))
            MM.sitDownToRest(state)
            return
        end

        MM.beginSet(state)
    end
end

local function onPlayerUpdate(player)
    -- The Auto All switch. Checked here rather than at load, because a
    -- player can turn the module off mid-session and a running loop
    -- has to stop when they do.
    if not MM.enabled() then return end
    if not player or not instanceof(player, "IsoPlayer") or not player:isLocalPlayer() then return end
    local state = MM.states[player:getPlayerNum()]
    if not state or not state.active then return end
    if now() < (state.nextThink or 0) then return end
    state.nextThink = now() + THINK_INTERVAL
    state.player = player
    MM.think(state)
end

local function onPlayerDeath(player)
    if player and MM.states[player:getPlayerNum()] then
        MM.stop(player, nil)
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnPlayerDeath.Add(onPlayerDeath)
