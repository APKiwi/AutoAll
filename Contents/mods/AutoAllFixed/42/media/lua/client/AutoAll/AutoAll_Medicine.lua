--[[
    Auto All - Treat All Wounds (Build 42 / SP + MP)
    ------------------------------------------------------------------
    Right click any body part in the Health window and the whole
    character gets patched up in one go: bullets out, glass out, burns
    washed, wounds disinfected, bandages on.

    Doing it by hand is several right clicks and a submenu per body
    part, and there are seventeen of them. After a fight that is a
    minute of clicking, and while something is still chasing you it is a
    minute you do not have.

    It is also the fastest way to train First Aid, which is why the
    glass-shard routine matters: stand on broken glass, pick the shards
    out, repeat. The clicking is the only hard part of that, and this
    removes it.

    ------------------------------------------------------------------
    Nothing here is rebalanced

    Every step queues the same vanilla timed action the Health window
    context menu queues, with the same item, in the same order:

        ISRemoveBullet   ISRemoveGlass   ISCleanBurn
        ISDisinfect      ISApplyBandage

    The XP, the times, the success rolls and the item consumption are
    the base game. The only thing this removes is the clicking.

    ------------------------------------------------------------------
    The order, and why it is that order

    Per body part, worst first:

      1. bullet    - a bandage over a bullet is a wasted bandage
      2. glass     - same
      3. burn      - isNeedBurnWash() has to be cleared before dressing
      4. disinfect - while the wound is still open
      5. bandage   - last, because bandaged() hides the part from every
                     other option. BaseHandler:isInjured() is

                         (HasInjury() or stitched() or getSplintFactor() > 0)
                         and not bandaged()

                     so dressing first would lock the rest out. Read off
                     the vanilla handler, not guessed.

    ------------------------------------------------------------------
    Which bandage

    A sterilised dressing first, then the strongest available. That is
    not a house preference - ISApplyBandage:perform() ends with

        SetBandaged(index, true, bandageLife, self.item:isAlcoholic(), ...)

    and the fourth argument is what marks the dressing as disinfected.
    So isAlcoholic() is the difference between a dressing that protects
    against infection and one that does not.

    Splints and stitches are deliberately NOT done. A stitch is a
    judgement call about a deep wound and needs needle and thread; a
    splint immobilises a limb for days. Neither is something to do to a
    character without being asked, and neither is repetitive enough to
    be worth automating.
]]

require "AutoAll/AutoAll_Core"
-- Used at load time to hook the panel, so a missing one has to be an
-- error here rather than a silent missing feature later.
require "XpSystem/ISUI/ISHealthPanel"

AutoAll = AutoAll or {}
local AA = AutoAll

if AA.medicineLoaded then return end
AA.medicineLoaded = true

AA.Medicine = AA.Medicine or {}
local Medicine = AA.Medicine

---------------------------------------------------------------------
-- finding supplies
--
-- The same containers the Health window itself searches:
-- BaseHandler:checkItems walks ISInventoryPaneContextMenu.getContainers
-- and recurses into every bag it finds. That covers the main inventory,
-- worn backpacks, satchels and fanny packs, and anything the loot
-- window has open - which is what was asked for.
---------------------------------------------------------------------

--- Every item within reach, bags included, as a flat list.
local function reachableItems(player)
    local out = {}
    local seen = {}

    local function sweep(container)
        if not container or seen[container] then return end
        seen[container] = true

        local items = container:getItems()
        if not items then return end

        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                if item:IsInventoryContainer() then
                    sweep(item:getInventory())
                else
                    out[#out + 1] = item
                end
            end
        end
    end

    sweep(player:getInventory())

    local containers = ISInventoryPaneContextMenu.getContainers(player)
    if containers then
        for i = 0, containers:size() - 1 do
            sweep(containers:get(i))
        end
    end

    return out
end

--- Picks the best item a score function accepts. Highest wins; a nil
--- score means the item is not eligible at all.
local function bestOf(items, score)
    local best, bestScore = nil, nil
    for _, item in ipairs(items) do
        local value = score(item)
        if value and (bestScore == nil or value > bestScore) then
            best, bestScore = item, value
        end
    end
    return best
end

---------------------------------------------------------------------
-- the item tests, copied from the vanilla handlers
---------------------------------------------------------------------

--- HRemoveBullet:checkItem and HRemoveGlass:checkItem, verbatim.
local function isProbe(item, tagName)
    local ok, result = pcall(function()
        if ItemTag and ItemTag[tagName] and item:hasTag(ItemTag[tagName]) then
            return true
        end
        local t = item:getType()
        return t == "Tweezers" or t == "SutureNeedleHolder"
    end)
    return ok and result == true
end

--- HDisinfect:checkItem, verbatim - a fluid container that is at least
--- 40 per cent alcohol with something in it, or a drainable at full
--- alcohol power.
local function disinfectantScore(item)
    local ok, score = pcall(function()
        if item:hasComponent(ComponentType.FluidContainer) then
            local fluid = item:getFluidContainer()
            local amount = fluid:getAmount()
            if amount > 0.15
                    and (fluid:getProperties():getAlcohol() / amount + 0.001) >= 0.4 then
                -- The fullest wins, so a nearly empty bottle is left for
                -- later rather than used up first.
                return amount
            end
            return nil
        end
        if item:IsDrainable() and item:getAlcoholPower() == 4.0 then
            -- getCurrentUsesFloat, not getUsedDelta.
            --
            -- > *Z3R0:* "Auto Medicine spams call nil every player update
            -- > ... 9500+ in one sitting"
            --
            -- getUsedDelta does not exist on a drainable at all. It is on
            -- Clothing; the drainable has setUsedDelta with NO matching
            -- getter, and the name symmetry is the whole trap. So every
            -- score of an alcohol drainable threw - and the pcall around
            -- it caught the value while the engine still dumped a full
            -- stack trace to console.txt on every single call, which is
            -- the flood. A pcall hides the result, never the trace.
            --
            -- getCurrentUsesFloat is what vanilla uses for "how full is
            -- this drainable" and is public on DrainableComboItem, which
            -- is the only class where IsDrainable() is not a hardcoded
            -- false.
            local uses = item:getCurrentUsesFloat()
            if type(uses) == "number" then
                -- An empty bottle scores 0, and 0 is truthy in Lua, so
                -- bestOf would happily pick it and queue a disinfect that
                -- has nothing to disinfect with. Not eligible at all.
                if uses <= 0 then return nil end
                return uses
            end
            return 0.5
        end
        return nil
    end)
    if ok then return score end
    return nil
end

--- A dressing vanilla scores as worthless. ISApplyBandage:complete does
--- `if string.match(type, "Dirty") then bandageLife = 0 end`, so a dirty
--- bandage is applied, lasts no time at all, risks infecting the wound and
--- - because bandaged() is now true - hides the part from the survey and
--- from every vanilla handler. Never worth doing on the player's behalf.
local function isDirtyBandage(item)
    local ok, dirty = pcall(function()
        local t = item:getType()
        return t ~= nil and string.match(t, "Dirty") ~= nil
    end)
    return ok and dirty == true
end

--- HApplyBandage:checkItem is getBandagePower() > 0. The ranking on top
--- of it is ours, and it is the point of the feature - see the header.
local function bandageScore(item)
    local ok, score = pcall(function()
        local power = item:getBandagePower()
        if not power or power <= 0 then return nil end
        if isDirtyBandage(item) then return nil end
        if item:isAlcoholic() then return 1000 + power end
        return power
    end)
    if ok then return score end
    return nil
end

--- The dirty ones bandageScore just refused, so the ending can say "no
--- clean bandage" rather than the flatly wrong "nothing within reach".
local function dirtyBandageScore(item)
    local ok, score = pcall(function()
        local power = item:getBandagePower()
        if not power or power <= 0 then return nil end
        if not isDirtyBandage(item) then return nil end
        return power
    end)
    if ok then return score end
    return nil
end

--- HCleanBurn:checkItem is getBandagePower() >= 2.
---
--- Alcoholic ranks BELOW plain here, the opposite of bandageScore. Washing
--- a burn consumes the cloth through UseAndSync and gains nothing from the
--- alcohol, while the bandage step needs it: isAlcoholic() is the fourth
--- argument to SetBandaged and the only thing marking a dressing as
--- disinfected. Preferring the sterilised cloth for the wash spent it here
--- and left the open wound the plain one.
local function burnWashScore(item)
    local ok, score = pcall(function()
        local power = item:getBandagePower()
        if not power or power < 2 then return nil end
        if item:isAlcoholic() then return power - 1000 end
        return power
    end)
    if ok then return score end
    return nil
end

---------------------------------------------------------------------
-- reading the character
---------------------------------------------------------------------

--- BaseHandler:isInjured, verbatim. A bandaged part answers false, which
--- is why the bandage step has to come last.
local function isInjured(part)
    local ok, result = pcall(function()
        return (part:HasInjury() or part:stitched() or part:getSplintFactor() > 0)
                and not part:bandaged()
    end)
    return ok and result == true
end

--- Does this part still want something this job knows how to do?
local function partNeedsWork(part)
    if not isInjured(part) then return false end

    local ok, needed = pcall(function()
        return part:haveBullet() or part:haveGlass()
            or part:isNeedBurnWash() or part:HasInjury()
    end)
    return ok and needed == true
end

--- Every body part that still wants attention, worst first, so a bullet
--- is dealt with before a graze however the list happens to be ordered.
function Medicine.survey(player)
    local out = {}

    local ok = pcall(function()
        local parts = player:getBodyDamage():getBodyParts()
        for i = 0, parts:size() - 1 do
            local part = parts:get(i)
            if part and partNeedsWork(part) then
                local rank = 4
                if part:haveBullet() then rank = 1
                elseif part:haveGlass() then rank = 2
                elseif part:isNeedBurnWash() then rank = 3 end
                out[#out + 1] = { part = part, rank = rank, index = i }
            end
        end
    end)
    if not ok then return {} end

    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.index < b.index
    end)
    return out
end

--- How many parts could be worked on right now, so the menu entry can
--- say what it is about to do before it is clicked.
function Medicine.countWork(player)
    return #Medicine.survey(player)
end

---------------------------------------------------------------------
-- one step
---------------------------------------------------------------------

-- How many think ticks the fetch gets to land before a step is given up
-- on. Eight quarter-second ticks is two seconds, the same window Auto
-- Reload's preparing phase uses and far longer than a transfer needs.
local PREPARE_ATTEMPTS = 8

--- Is the item where the vanilla action is about to look for it?
---
--- ISDisinfect:isValid tests containsID on the player inventory and
--- ISApplyBandage:start re-looks its item up with getItemById, so this
--- asks the same question rather than trusting the transfer to have
--- landed. transferIfNeeded moves the item into the main inventory, so a
--- non-recursive containsID is the right test after it.
local function inInventory(player, item)
    if not item then return false end
    local ok, found = pcall(function()
        local inventory = player:getInventory()
        if inventory:containsID(item:getID()) then return true end
        return inventory:getItemById(item:getID()) ~= nil
    end)
    return ok and found == true
end

--- Marks a part as one this job will not touch, and says why once.
local function block(task, entry, reason)
    if task.blocked[entry.index] then return end
    task.blocked[entry.index] = reason
    task.blockedCount = task.blockedCount + 1
end

--- Works out the single next thing to do, and queues the FETCH for it.
---
--- Deliberately one action per think tick rather than a batch. Every one
--- of these changes the state the next decision reads - taking a bullet
--- out makes the part bleed, a bandage hides the part from every other
--- option - so a batch planned up front would be planned against a body
--- that no longer exists by the time it ran. Same lesson as the wringing
--- job in Auto Clean: build the action when it is its turn, not when the
--- job is planned.
---
--- The action itself is NOT built here. transferIfNeeded queues a timed
--- action of its own - the character walks over and moves the item - so an
--- action built in this same tick is validated against an inventory the
--- transfer has not reached. In single player that is harmless. On a
--- client ISDisinfect fails containsID and is dropped, and ISApplyBandage
--- is worse: its isValid on a client returns itemWasPresent, which is only
--- "the item was non-nil at construction", so it starts, start() re-looks
--- the item up by id and gets nil, and complete() throws inside vanilla
--- with the bar sitting at 100 per cent. So the plan is handed back and
--- run a tick later, once the queue has drained. Same shape as Auto
--- Reload's preparing phase (Reload 290-327).
---
--- @return table|nil  the plan, or nil when there is nothing left to do
local function planNextStep(task)
    local player = task.player
    local work   = Medicine.survey(player)
    if #work == 0 then return nil end

    local supplies = reachableItems(player)
    local bandage  = bestOf(supplies, bandageScore)

    local function plan(kind, entry, item)
        if item then
            ISInventoryPaneContextMenu.transferIfNeeded(player, item)
        end
        return { kind = kind, part = entry.part, index = entry.index,
                 item = item, tries = 0 }
    end

    for _, entry in ipairs(work) do
        local part    = entry.part
        local blocked = false

        if part:haveBullet() then
            local probe = bestOf(supplies, function(item)
                if isProbe(item, "REMOVE_BULLET") then return 1 end
                return nil
            end)
            if probe then
                return plan("bullet", entry, probe)
            end
            -- No probe, so this part is BLOCKED, not merely skipped. It
            -- must not fall through to the bandage step: bandaged() makes
            -- BaseHandler:isInjured() false, which hides the part from
            -- this survey and from vanilla's Remove Bullet as well, and
            -- the bullet stays in until the player strips the dressing
            -- off by hand.
            blocked = true

        elseif part:haveGlass() then
            -- Unlike every other step this one has a vanilla fallback
            -- with no item at all - the Health menu offers "Hands" - so a
            -- character with no tweezers still gets the shards out, which
            -- is exactly the training routine this was asked for.
            local probe = bestOf(supplies, function(item)
                if isProbe(item, "REMOVE_GLASS") then return 1 end
                return nil
            end)
            return plan("glass", entry, probe)

        elseif part:isNeedBurnWash() then
            local cloth = bestOf(supplies, burnWashScore)
            if cloth then
                return plan("burn", entry, cloth)
            end
            -- Same as the bullet: dressing an unwashed burn hides it.
            blocked = true
        end

        if blocked then
            block(task, entry, "tool")
        else
            -- Disinfect once per part, and only while the wound is still
            -- open. Tracked on the task rather than read off the body,
            -- because there is no "this wound is disinfected" flag to read -
            -- that state lives on the dressing, which does not exist yet.
            --
            -- Gated on there being a bandage to follow it, because a
            -- disinfect is invisible to bodyState: without that gate a
            -- character with alcohol and no dressings spends a dose per
            -- part for twelve parts and then reports itself stuck.
            if bandage and not part:bandaged() and not task.disinfected[entry.index]
                    and AA.opt("medDisinfect") then
                local alcohol = bestOf(supplies, disinfectantScore)
                if alcohol then
                    return plan("disinfect", entry, alcohol)
                end
            end

            if not part:bandaged() then
                if bandage then
                    return plan("bandage", entry, bandage)
                end
                -- Nothing clean. If the only candidate was a dirty one,
                -- say so rather than reporting an empty inventory.
                if bestOf(supplies, dirtyBandageScore) then
                    if not task.noClean[entry.index] then
                        task.noClean[entry.index] = true
                        task.noCleanCount = task.noCleanCount + 1
                    end
                end
            end
        end
    end

    return nil
end

--- Phase two: the fetch has drained, so build the action now.
---
--- @return boolean  true while the step is still being worked on
local function runPlan(task)
    local player  = task.player
    local plan    = task.plan
    local doctor  = player
    local patient = player
    local part    = plan.part

    if plan.item and not inInventory(player, plan.item) then
        -- On a client the transfer settles through the server and can
        -- still be in flight after its action has drained.
        plan.tries = plan.tries + 1
        if plan.tries <= PREPARE_ATTEMPTS then return true end

        print("[AutoAll] medicine: " .. tostring(plan.kind)
                .. " item never arrived in the inventory")
        task.plan    = nil
        -- Counts as a step that changed nothing, so the no-progress
        -- detector ends the job rather than retrying forever.
        task.pending = plan.kind
        return true
    end

    if plan.kind == "bullet" then
        ISTimedActionQueue.add(ISRemoveBullet:new(doctor, patient, part))
    elseif plan.kind == "glass" then
        -- No probe means the vanilla hands variant.
        ISTimedActionQueue.add(ISRemoveGlass:new(doctor, patient, part, plan.item == nil))
    elseif plan.kind == "burn" then
        ISTimedActionQueue.add(ISCleanBurn:new(doctor, patient, plan.item, part))
    elseif plan.kind == "disinfect" then
        ISTimedActionQueue.add(ISDisinfect:new(doctor, patient, plan.item, part))
        -- Not marked disinfected yet. The action can still be dropped, and
        -- a wound flagged as done that never was gets bandaged dirty. The
        -- flag is promoted only once the dose has visibly been spent.
        task.disinfectPending = {
            index = plan.index,
            item  = plan.item,
            dose  = disinfectantScore(plan.item),
        }
    elseif plan.kind == "bandage" then
        ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, plan.item, part, true))
    end

    task.plan    = nil
    task.pending = plan.kind
    return true
end

--- Did the disinfect queued last step actually run?
---
--- bodyState carries no disinfect flag, so the only evidence is the
--- disinfectant itself: ISDisinfect spends fluid or a use, and
--- disinfectantScore is exactly how full it is. A dose that went down
--- promotes the flag AND counts as progress, so a run of disinfects is
--- not mistaken for a job doing nothing.
---
--- @return boolean  true when a disinfect is confirmed
local function confirmDisinfect(task)
    local marker = task.disinfectPending
    if not marker then return false end
    task.disinfectPending = nil

    local after = disinfectantScore(marker.item)
    local spent = after == nil
            or marker.dose == nil
            or after < marker.dose - 0.0001

    if spent then
        task.disinfected[marker.index] = true
        return true
    end
    return false
end

---------------------------------------------------------------------
-- the job
---------------------------------------------------------------------

-- A body has seventeen parts and each can need several passes. This is a
-- runaway guard, not a limit anyone should meet.
local MAX_STEPS = 200

-- Steps in a row that queued something and changed nothing. A failed
-- roll is normal - vanilla can fail to get a shard out - so this has to
-- be generous enough not to give up on bad luck.
local MAX_NO_PROGRESS = 12

--- A cheap fingerprint of everything this job can change, so "did that
--- action actually do anything" is answered by asking the body rather
--- than by trusting the queue. Same rule as Auto Rip's
--- confirmPendingCrafts and Auto Reload's ammo count.
local function bodyState(player)
    local parts = {}
    pcall(function()
        local list = player:getBodyDamage():getBodyParts()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            parts[#parts + 1] = table.concat({
                p:haveBullet() and 1 or 0,
                p:haveGlass() and 1 or 0,
                p:isNeedBurnWash() and 1 or 0,
                p:bandaged() and 1 or 0,
                p:bleeding() and 1 or 0,
            }, "")
        end
    end)
    return table.concat(parts, "|")
end

---------------------------------------------------------------------
-- why this job does not stop when health goes down
--
-- > *Barbiehunter:* "As I just tried Treat all Wounds after I hurted
-- > myself it always stops with the Message of stopping, of taking
-- > damage. This is quiet confusing, as that's the whole Point about it
-- > is to fix the damage"
--
-- Exactly right, and the cause is structural rather than a slip. The
-- shared safety check stops a task when getOverallBodyHealth() drops.
-- An open wound bleeds; bleeding lowers that number every tick. So the
-- one job whose entire purpose is to make the bleeding stop was using
-- the bleeding as its abort signal, and aborted on its first think.
--
-- The task therefore takes over the decision through the expectedDamage
-- hook. Health going down is the condition being treated. What still
-- stops it is a wound the character did NOT have when the job started -
-- and specifically a bite or a scratch, because those two only come
-- from something attacking, while every other flag on a body part can
-- be moved by the treatment itself.
--
-- That last point is not a guess. ISRemoveBullet:complete() calls
-- setHaveBullet(false, doctorLevel) and syncs with a mask that names
-- BD_deepWounded and BD_deepWoundTime (0x40460108), so taking a bullet
-- out can leave a deep wound behind. deepWounded, bleeding and
-- bleedingTime are all things this job causes on purpose; bitten and
-- scratched are not.
---------------------------------------------------------------------

--- One character per part: bitten, scratched. Compared against the same
--- print taken at the start, so a 0 that becomes a 1 is a new attack.
local function attackPrint(player)
    local parts = {}
    pcall(function()
        local list = player:getBodyDamage():getBodyParts()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            parts[#parts + 1] = (p:bitten() and "1" or "0")
                    .. (p:scratched() and "1" or "0")
        end
    end)
    return table.concat(parts)
end

--- True when nothing has bitten or scratched the character since the job
--- started. A flag going the other way - a wound this job closed - is
--- not an attack, so only 0 -> 1 counts.
local function noNewAttack(task)
    local before = task.attackPrint
    local after  = attackPrint(task.player)
    if not before or #before ~= #after then
        task.attackPrint = after
        return true
    end
    for i = 1, #after do
        if before:sub(i, i) == "0" and after:sub(i, i) == "1" then
            return false
        end
    end
    task.attackPrint = after
    return true
end

local function think(task)
    local player = task.player

    if AA.isQueueBusy(player) then return end

    -- The fetch queued last tick has drained. Now, and only now, is the
    -- treatment built - see the note on planNextStep.
    if task.plan then
        runPlan(task)
        return
    end

    if task.pending then
        local disinfected = confirmDisinfect(task)
        local state = bodyState(player)
        if state ~= task.lastState or disinfected then
            task.done       = task.done + 1
            task.lastState  = state
            task.noProgress = 0
        else
            task.noProgress = task.noProgress + 1
            if task.noProgress >= MAX_NO_PROGRESS then
                print("[AutoAll] medicine: " .. tostring(task.noProgress)
                        .. " steps in a row changed nothing, last was "
                        .. tostring(task.pending))
                AA.stop(player, getText("UI_AA_med_stuck", task.done), true)
                return
            end
        end
        task.pending = nil
    end

    task.steps = task.steps + 1
    if task.steps > MAX_STEPS then
        -- Two hundred steps is a runaway, not a finished job. Reporting it
        -- as done sends a player off still bleeding.
        AA.stop(player, getText("UI_AA_med_stuck", task.done), true)
        return
    end

    local plan = planNextStep(task)
    if not plan then
        if task.blockedCount > 0 then
            AA.stop(player, getText("UI_AA_med_blocked", task.blockedCount), true)
        elseif task.noCleanCount > 0 then
            AA.stop(player, getText("UI_AA_med_noclean", task.noCleanCount), true)
        elseif task.done == 0 then
            AA.stop(player, getText("UI_AA_med_nosupplies"), true)
        else
            AA.stop(player, getText("UI_AA_med_done", task.done), false)
        end
        return
    end

    task.plan = plan
end

function Medicine.start(player)
    if not player then return end

    local work = Medicine.survey(player)
    if #work == 0 then
        HaloTextHelper.addGoodText(player, getText("UI_AA_med_nothing"))
        return
    end

    local task = {
        kind        = "medicine",
        player      = player,
        think       = think,
        steps       = 0,
        done        = 0,
        noProgress  = 0,
        pending     = nil,
        -- The step whose fetch is in flight, run a tick later.
        plan        = nil,
        disinfected = {},
        -- A queued disinfect, promoted into disinfected once its dose is
        -- confirmed spent.
        disinfectPending = nil,
        -- Parts left alone because a step they need has no item, and parts
        -- with nothing but a dirty bandage. Both are reported at the end so
        -- the player knows to deal with them by hand.
        blocked      = {},
        blockedCount = 0,
        noClean      = {},
        noCleanCount = 0,
        lastState   = bodyState(player),
        attackPrint = attackPrint(player),
        -- Bleeding is the condition, not the danger. See the block above
        -- attackPrint.
        expectedDamage = noNewAttack,
        -- A bandage that never finishes leaves the character bleeding
        -- with the mod apparently still working, which is the worst
        -- possible way for this particular job to fail. Reported by
        -- Talkierplacebo2 on a hosted game: "healing not actually
        -- finishing the job, it just gets to 99% done and never
        -- continues, so I have to turn the mod off before my character
        -- bleeds out."
        stallTimeout = 30000,
        -- Treating yourself is a standing-still job, and a player who
        -- walks off has decided to stop. Same as every other module.
        allowMove   = false,
        startText   = getText("UI_AA_med_started", #work),
    }

    AA.startTask(task)
end

Medicine.onStart = function(player)
    Medicine.start(player)
end

Medicine.onStop = function(player)
    AA.stop(player, getText("UI_AA_stopped"), false)
end

---------------------------------------------------------------------
-- the menu, on the Health window
--
-- Appended to ISHealthPanel:doBodyPartContextMenu rather than replacing
-- it: that function builds thirteen vanilla handlers and adds an option
-- for each, and every one of them has to keep working. Ours goes on the
-- end and is then lifted to the top by AA.liftOptions, which this module
-- has to call ITSELF - the core registers that pass on the two inventory
-- and world context menu events, and the Health window is neither.
---------------------------------------------------------------------

local function addMedicineMenu(panel, context)
    if not AA.enabled("medicine") then return end

    -- The Health window can be showing somebody else - a doctor treating
    -- a patient in multiplayer. This job treats the character whose
    -- window it is, so it is only offered on your own.
    if panel.otherPlayer then return end

    local player = panel.character
    if not player or player:isDead() then return end

    if AA.isRunning(player, "medicine") then
        AA.addOption(context, getText("UI_AA_med_stop"), player, Medicine.onStop)
        return
    end

    local work = Medicine.countWork(player)

    local option = AA.addOption(context, getText("UI_AA_med_option"), player, Medicine.onStart)
    local tooltip = ISInventoryPaneContextMenu.addToolTip()

    if work == 0 then
        -- Greyed out with the reason rather than hidden. A vanished entry
        -- reads as a broken mod - see the design rules.
        option.notAvailable = true
        tooltip.description = getText("UI_AA_med_nothing")
    else
        tooltip.description = getText("UI_AA_med_option_tt", work)
    end
    option.toolTip = tooltip
end

local function installMenu()
    if AA.medicineMenuInstalled then return end
    if not ISHealthPanel or type(ISHealthPanel.doBodyPartContextMenu) ~= "function" then
        print("[AutoAll] medicine: ISHealthPanel.doBodyPartContextMenu is missing")
        return
    end
    AA.medicineMenuInstalled = true

    local original = ISHealthPanel.doBodyPartContextMenu

    ISHealthPanel.doBodyPartContextMenu = function(self, bodyPart, x, y)
        original(self, bodyPart, x, y)

        -- The menu vanilla has just built and filled.
        --
        -- ISContextMenu.get(playerNum, x, y) is what it called, and that
        -- CLEARS the menu before handing it back - calling it again here
        -- would wipe every option vanilla just added. getPlayerContextMenu
        -- is the getter underneath it that does not clear, which is the
        -- only safe way for an appended hook to reach the live menu.
        local playerNum = self.otherPlayer and self.otherPlayer:getPlayerNum()
                or self.character:getPlayerNum()

        local context = nil
        pcall(function()
            context = getPlayerContextMenu(playerNum)
        end)
        if not context then return end

        local previous = AA.currentModule
        AA.currentModule = "medicine"
        local ok, err = pcall(addMedicineMenu, self, context)
        AA.currentModule = previous

        if not ok then
            print("[AutoAll] medicine menu error: " .. tostring(err))
            return
        end

        -- Two things vanilla already did before we got here, both of which
        -- have to be undone or repeated.
        --
        -- 1. It hides the menu when nothing was added:
        --
        --        if self.blockingMessage or context:isEmpty() then
        --            context:setVisible(false)
        --        end
        --
        --    That runs before this hook, so on a body part vanilla has no
        --    options for - which is most of them, most of the time - our
        --    entry would have been added to a menu already told not to
        --    draw. Right clicking a healthy limb to start treating the
        --    injured ones would have done nothing at all.
        --
        -- 2. It never runs the mod's ordering pass. That is registered on
        --    OnFillInventoryObjectContextMenu and OnFillWorldObjectContextMenu
        --    only, and the Health window is neither, so without this our
        --    entry sits underneath thirteen vanilla medical options - at
        --    the bottom of the one menu whose whole point is being quick.
        pcall(function()
            if not context:isEmpty() then
                AA.liftOptions(context)
                if not self.blockingMessage then
                    context:setVisible(true)
                    context:bringToTop()
                end
            end
        end)
    end
end

Events.OnGameStart.Add(installMenu)
