--[[
    [B42.20] Muscle Manager (Build 42 / SP + MP)
    ------------------------------------------------------------------
    Reading between sets.

    > *Ayako-Chan:* "Would you add an option to read skill books while
    > resting between sets? I'm asking because I always do this whenever
    > I have those books in my inventory: I train, and then when I get
    > tired, I sit down and read until I'm fully rested. Then I stop
    > reading and go back to training"

    Nothing here is new behaviour: it queues the vanilla ISReadABook and
    it stops it, which is exactly what the player does by hand.

    Two facts hold the whole thing up, both read out of the game rather
    than assumed.

    * Reading while seated is allowed, and vanilla likes it.
      ISReadABook:isValid() (ISReadABook.lua:5-19) has no posture check
      at all, and getDuration() gives a 10 per cent speed bonus while
      sitting (:476-478). ISRestAction.lua:46 carries the developer's own
      comment - "Removed this as being an action, this way we can still
      passively regain endurance and read at the same time".

    * Endurance recovery does not care that an action is running.
      IsoPlayer.updateEndurance() branches on isSitOnGround() /
      isSittingOnFurniture() / isResting() only, and hands over to
      updateEnduranceWhileSitting(), which reads sittingEnduranceMultiplier
      and the sandbox regen multiplier and nothing else. Read from the
      bytecode. So the rest is neither slowed nor sped up.

    The one thing that has to be got right is when the book goes DOWN.
    MuscleManager_Core's resting branch waits for the action queue to
    drain before it will start the next set, so a book left open would be
    deciding how long the rest lasts - and would also switch the pain and
    food options off, because tryTreatPain and tryEat both refuse to
    queue anything while an action is running.

    MM.restReadShouldStop is the single place that decides, and both the
    "put it down" and the "pick it up" call sites ask it, so the two can
    never disagree and thrash.

    From upstream Auto All, 2026-09-06.

    One limit of this fork's own making. Resting on furniture queues
    vanilla's ISRestAction, and tryRestRead refuses to queue on top of a
    running action, so a rest spent on a couch is a rest spent without a
    book. Sitting on the ground is reportEvent("EventSitOnGround") and
    not an action at all, so the default rest does read. Stacking the two
    would mean deciding which of them owns the end of the rest, and that
    is a bigger change than taking this feature.
]]

MuscleManager = MuscleManager or {}
local MM = MuscleManager

if MM.restReadLoaded then return end
MM.restReadLoaded = true

local function currentAction(player)
    local queue = ISTimedActionQueue.getTimedActionQueue(player)
    return queue and queue.queue[1] or nil
end

local function isLiteraturePredicate(item)
    return instanceof(item, "Literature")
end

--- The best book on the character that still teaches something, or nil.
---
--- Judged by Auto All's own Read.appraise, so this obeys vanilla's "too
--- complicated" and "too simple" rules, skips books already read out,
--- skips magazines whose recipes are all known, and follows the player's
--- existing "read skill books" and "read recipe magazines" switches. No
--- new option has to exist for any of that.
---
--- The character's own inventory and bags only. Auto Read's Read.collect
--- would also reach into nearby containers, and walking off to a shelf
--- in the middle of a rest would fight the return-to-the-training-spot
--- logic - and is not what was asked for ("whenever I have those books
--- in my inventory").
function MM.findRestBook(player)
    local Read = AutoAll and AutoAll.Read
    if not Read or type(Read.appraise) ~= "function" then return nil end

    local inventory = player:getInventory()
    if not inventory then return nil end

    local items = inventory:getAllEvalRecurse(isLiteraturePredicate, ArrayList.new())
    if not items then return nil end

    local best, bestOrder = nil, nil
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local ok, entry = pcall(Read.appraise, player, item)
        if ok and entry and (bestOrder == nil or entry.order < bestOrder) then
            best, bestOrder = item, entry.order
        end
    end
    return best
end

--- True when the rest has something better to do than read.
---
--- The first clause is the point of the feature: the rest ends on
--- endurance, never on the last page. The other two exist because
--- tryTreatPain and tryEat both open with "if currentAction(player) then
--- return false end" - so a book left open across them would quietly
--- turn those two options off.
function MM.restReadShouldStop(state)
    local player = state.player
    if not player then return true end

    local endurance = MM.getEndurance(player) * 100
    local moodles = player:getMoodles()
    local pain = moodles:getMoodleLevel(MoodleType.PAIN)

    if endurance >= MM.opt("resumeAt") and not MM.isTooTired(player) and pain <= 3 then
        return true
    end
    if MM.opt("treatPain") and pain >= MM.opt("painLevel") then
        return true
    end
    if MM.opt("autoEat")
            and moodles:getMoodleLevel(MoodleType.HUNGRY) >= MM.opt("eatAt")
            and moodles:getMoodleLevel(MoodleType.FOOD_EATEN) < 3 then
        return true
    end
    if player:tooDarkToRead() then return true end

    return false
end

--- Queues one book. Returns true when it queued something.
function MM.tryRestRead(state)
    if not MM.opt("autoRead") then return false end

    local player = state.player
    if not player then return false end
    if state.phase ~= "resting" then return false end
    if player:hasTrait(CharacterTrait.ILLITERATE) then return false end
    if MM.restReadShouldStop(state) then return false end
    if state.reading and ISTimedActionQueue.hasAction(state.reading) then return false end

    -- Same rule the rest of this loop follows: never queue on top of
    -- something. sitDownToRest may have just queued a walk to a couch.
    if currentAction(player) then return false end

    local book = MM.findRestBook(player)
    if not book then return false end

    -- Vanilla's action and nothing else. The pages, the XP multiplier,
    -- the sitting speed bonus and the multiplayer sync are all the base
    -- game's, and an interrupted read keeps its pages: ISReadABook:update
    -- writes setAlreadyReadPages every tick and getDuration reads them
    -- back as the start page, so a book read in slices across several
    -- rests behaves exactly like one the player kept cancelling.
    local action = ISReadABook:new(player, book)
    ISTimedActionQueue.add(action)
    state.reading = action

    MM.say(state, getText("UI_MM_reading", book:getName()), false)
    MM.log("reading " .. tostring(book:getFullType()) .. " while resting")
    return true
end

--- Puts the book down. Returns true while it is still dealing with one -
--- the caller should return and come back next tick.
function MM.stopRestRead(state)
    if not state then return false end

    local action = state.reading
    if not action then return false end

    if not ISTimedActionQueue.hasAction(action) then
        state.reading = nil
        return false
    end

    -- Queued but not begun yet: ISBaseTimedAction only builds .action
    -- when it starts, and forceStop on a nil would throw. One think tick.
    if not action.action then return true end

    pcall(function() action.action:forceStop() end)
    state.reading = nil
    return true
end
