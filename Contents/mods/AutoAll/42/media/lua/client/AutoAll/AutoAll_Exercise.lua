--[[
    Auto All - making the Auto Exercise switch stick (Build 42 / SP + MP)
    ------------------------------------------------------------------
    > *Panda:* "I disabled Auto Exercise when it appeared but the Muscle
    > Manager seems to still be taking effect. Is it possible to have a
    > toggle to turn Muscle Manager off or better, just use a separate mod
    > entry for it so people who only really wanted the Auto All
    > functionality can choose not to enable Muscle Manager on the
    > modlist?"

    The toggle exists and it is wired up: MuscleManager_Config defines
    MM.enabled(), which asks AutoAll.enabled("exercise"), and both
    MuscleManager_Core's onPlayerUpdate and MuscleManager_UI's
    ISFitnessUI:initialise return early when it says no.

    So why does it not stick? Because the standalone Muscle Manager
    (Workshop 3775968752) can be installed as well, and both mods ship
    files at the same relative paths:

        media/lua/client/MuscleManager/MuscleManager_Core.lua
        media/lua/client/MuscleManager/MuscleManager_Config.lua
        media/lua/client/MuscleManager/MuscleManager_UI.lua

    Project Zomboid keeps one file per relative path, so whichever mod
    loads later wins - all nine of them, together. The standalone has no
    MM.enabled() and no gates, because it has no Auto All tickbox to
    answer to. When it wins the race, the loop that runs is the ungated
    one and the Auto All switch is decoration.

    That cannot be fixed inside a file the standalone replaces. It can be
    fixed from here, because AutoAll_Exercise.lua exists only in this mod
    and is therefore always loaded.

    So the switch is enforced from the outside instead of asked politely
    from the inside: while Auto Exercise is off, any running training loop
    is stopped and the AUTO box is held unticked, whoever built it.

    ------------------------------------------------------------------
    On the separate mod entry

    Panda's second suggestion - ship Muscle Manager as its own entry in
    the mod list - would solve this outright, and is not done here. A new
    mod entry starts unticked, so every player currently using Auto
    Exercise would lose it on update with nothing on screen to explain
    why. Trading one silent surprise for another is not a fix. It is a
    real option, and it is the author's call rather than this file's.
]]

require "AutoAll/AutoAll_Core"

AutoAll = AutoAll or {}
local AA = AutoAll

if AA.exerciseGateLoaded then return end
AA.exerciseGateLoaded = true

-- Said once per session, not once per tick. Having to step in means the
-- ungated copy is the one running, and that is worth a line in
-- console.txt: it is the difference between "the option is broken" and
-- "you have both mods installed".
local warned = false

-- With nothing readable to say whether a loop is running, the blind stop
-- below cannot tell whether it worked, so it is rate limited rather than
-- retried on every tick.
local BLIND_STOP_EVERY = 5000   -- ms
local blindStopAt = 0

--- True when the Muscle Manager that actually loaded is one that never
--- asks Auto All anything.
local function ungatedCopy()
    return MuscleManager ~= nil and type(MuscleManager.enabled) ~= "function"
end

--- Unticks the AUTO box itself, not just the flag behind it.
---
--- ISFitnessUI writes the widget's state back into MuscleManager.autoTicked,
--- so clearing only the flag left the box drawn ticked. The player pressed
--- OK, a set started, this gate killed it a tick later, and the box was
--- still ticked ready to do it again.
---
--- Kept as cheap as it can be, because the only caller runs from
--- OnPlayerUpdate and therefore pays this on every frame. A closed panel and
--- an already unticked box are both resting states rather than events, so
--- both leave before doing any work, and the state is read off the widget
--- instead of being written over blind: ISTickBox:isSelected(index) reads the
--- same self.selected table that setSelected(index, value) writes, so asking
--- costs a table lookup and telling costs nothing when there is nothing to
--- tell. Both calls go through pcall because ISTickBox errors on an index it
--- does not have, and the box this file is holding down was built elsewhere.
local function untickWidget(player)
    local panels = ISFitnessUI and ISFitnessUI.instance
    if type(panels) ~= "table" then return end
    local panel = panels[player:getPlayerNum() + 1]
    if not panel or not panel.mmAuto then return end

    local box = panel.mmAuto
    if type(box.isSelected) == "function" then
        local ok, ticked = pcall(box.isSelected, box, 1)
        if ok and not ticked then return end
    end
    pcall(box.setSelected, box, 1, false)
end

--- Whatever loaded, hold it to the switch.
local function enforce(player)
    if not player or not instanceof(player, "IsoPlayer") or not player:isLocalPlayer() then return end
    if MuscleManager == nil then return end
    if AA.enabled("exercise") then return end

    -- The AUTO box on the vanilla Fitness panel remembers itself between
    -- openings, and MM.autoDefault can tick it on its own. Held down
    -- rather than set once, because the panel writes it back.
    if MuscleManager.autoTicked == true then
        MuscleManager.autoTicked = false
    end
    untickWidget(player)

    local states = MuscleManager.states
    if type(states) == "table" then
        local state = states[player:getPlayerNum()]
        if not state or state.active ~= true then return end

        if not warned then
            warned = true
            print("[AutoAll] exercise is switched off but a Muscle Manager loop was running"
                    .. (ungatedCopy() and " - the standalone Muscle Manager is loaded and"
                        .. " its files replace the bundled ones, so it never sees the switch."
                        .. " Stopping it from here." or " - stopping it."))
        end

        if type(MuscleManager.stop) == "function" then
            -- Said out loud. Killing a set the player asked for without a
            -- word looks like the mod failing rather than the switch
            -- working. Translated here rather than at the top of the
            -- function because getText is a call into Java and this runs
            -- from OnPlayerUpdate: the switch being off is a resting state,
            -- and only the stop that actually happens should pay for it.
            pcall(MuscleManager.stop, player, getText("UI_AA_exercise_off"), true)
        else
            -- Nothing to call. Take the state away, which is what every
            -- decision in that loop is keyed on.
            state.active = false
            states[player:getPlayerNum()] = nil
        end
        return
    end

    -- MuscleManager.states is not the table this file expects, so there is
    -- nothing to read to decide whether a loop is running at all. Ask it to
    -- stop anyway: stopping a loop that is not running is a no-op in every
    -- build seen so far, and the alternative is an ungated loop carrying on
    -- with the switch off, which is the exact bug this file exists for.
    if type(MuscleManager.stop) ~= "function" then return end
    local at = getTimestampMs()
    if at - blindStopAt < BLIND_STOP_EVERY then return end
    blindStopAt = at

    if not warned then
        warned = true
        print("[AutoAll] exercise is switched off and MuscleManager.states is not a table"
                .. " - stopping any loop blind, since there is no state to read.")
    end
    -- Translated at the call for the same reason as above: this line is
    -- reached at most once every BLIND_STOP_EVERY milliseconds, not once a
    -- frame.
    pcall(MuscleManager.stop, player, getText("UI_AA_exercise_off"), true)
end

Events.OnPlayerUpdate.Add(enforce)

--- Hand the gate to a Muscle Manager that does not have one.
---
--- Harmless when the bundled copy won - it already defines this and the
--- check below leaves it alone. Worth doing for the case where a future
--- standalone starts asking: it gets the right answer without needing to
--- know Auto All exists.
Events.OnGameStart.Add(function()
    if MuscleManager == nil then return end
    if type(MuscleManager.enabled) == "function" then return end

    MuscleManager.enabled = function()
        return AA.enabled("exercise")
    end
    print("[AutoAll] exercise: installed the missing MuscleManager.enabled gate")
end)
