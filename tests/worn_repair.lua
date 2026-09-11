local failures = 0
local root = arg[0]:match("^(.*)/tests/worn_repair%.lua$") or "."

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ")
                .. ": expected " .. tostring(expected)
                .. ", got " .. tostring(actual), 2)
    end
end

local function run(name, body)
    local ok, message = pcall(body)
    if ok then
        print("ok - " .. name)
    else
        failures = failures + 1
        print("not ok - " .. name)
        print("  " .. tostring(message))
    end
end

local function list(values)
    local result = { values = values or {} }

    function result:size()
        return #self.values
    end

    function result:get(index)
        return self.values[index + 1]
    end

    function result:add(value)
        self.values[#self.values + 1] = value
    end

    function result:contains(value)
        for _, candidate in ipairs(self.values) do
            if candidate == value then return true end
        end
        return false
    end

    return result
end

local function item(id, itemType, fabricType)
    return {
        getID = function() return id end,
        getType = function() return itemType end,
        getFullType = function() return "Base." .. itemType end,
        getDisplayName = function() return itemType end,
        getFabricType = function() return fabricType end,
        getContainer = function() return nil end,
    }
end

local function fixture()
    local part = "Groin"
    local visibleHole = true
    local actualHole = true
    local patch = nil
    local queuedRepairs = {}
    local stopped = nil

    local needle = item(1, "Needle")
    local thread = item(2, "Thread")
    local sheet1 = item(3, "RippedSheets", "Cotton")
    local sheet2 = item(4, "RippedSheets", "Cotton")
    local items = { needle, thread, sheet1, sheet2 }
    local inventory = {}

    function inventory:getItemById(id)
        for _, candidate in ipairs(items) do
            if candidate:getID() == id then return candidate end
        end
        return nil
    end

    function inventory:getAllEvalRecurse(predicate, out)
        for _, candidate in ipairs(items) do
            if predicate(candidate) then out:add(candidate) end
        end
        return out
    end

    local clothing = {
        className = "Clothing",
        getID = function() return 10 end,
        getType = function() return "Trousers_ArmyService" end,
        getDisplayName = function() return "Military Pants" end,
        getContainer = function() return inventory end,
        getFabricType = function() return "Cotton" end,
        getCoveredParts = function() return list({ part }) end,
        getPatchType = function() return patch end,
        getVisual = function()
            return {
                getHole = function()
                    return visibleHole and 1 or 0
                end,
            }
        end,
    }
    items[#items + 1] = clothing

    local player = {
        getInventory = function() return inventory end,
        isDead = function() return false end,
    }

    local task = nil
    AutoAll = {
        opt = function() return nil end,
        enabled = function() return false end,
        holds = function() return true end,
        isQueueBusy = function() return false end,
        isRunning = function() return false end,
        registerMenu = function() end,
        say = function() end,
        stop = function(_, text, bad)
            stopped = { text = text, bad = bad }
        end,
        startTask = function(started)
            task = started
            return true
        end,
        findItemByTag = function() return nil end,
    }

    AutoAll.findItem = function(_, wanted)
        for _, candidate in ipairs(items) do
            if candidate:getType() == wanted then return candidate end
        end
        return nil
    end

    Events = {
        OnFillInventoryObjectContextMenu = {},
    }
    ArrayList = { new = function() return list() end }
    ItemTag = { SEWING_NEEDLE = "SewingNeedle", THREAD = "Thread" }
    HaloTextHelper = { addBadText = function() end }
    ISInventoryPane = {}
    ISInventoryPaneContextMenu = {
        getContainers = function() return list() end,
        repairClothing = function(_, _, repairedPart)
            local action = {}

            function action:complete()
                -- This is the branch in vanilla Clothing.addPatch. A repair
                -- that completes after the hole is gone adds padding.
                if actualHole then
                    actualHole = false
                else
                    patch = "CottonPatch"
                end
            end

            action.part = repairedPart
            queuedRepairs[#queuedRepairs + 1] = action
        end,
    }
    ISGarmentUI = { initialise = function() end, render = function() end }
    UIFont = { Small = "Small" }
    SandboxVars = {}

    _G.require = function() return true end
    _G.instanceof = function(value, className)
        return value ~= nil and value.className == className
    end
    _G.isClient = function() return true end
    _G.getText = function(key) return key end
    _G.getTextManager = function()
        return {
            getFontHeight = function() return 12 end,
            MeasureStringX = function() return 40 end,
        }
    end

    local chunk, message = loadfile(root
            .. "/Contents/mods/AutoAll/42/media/lua/client/AutoAll/AutoAll_Tailoring.lua")
    if not chunk then error(message) end
    chunk()

    return {
        player = player,
        clothing = clothing,
        repairs = queuedRepairs,
        getTask = function() return task end,
        settleVisual = function() visibleHole = actualHole end,
        getPatch = function() return patch end,
        getStop = function() return stopped end,
    }
end

run("a delayed worn visual never schedules padding over a repaired hole", function()
    local game = fixture()

    AutoAll.Tailor.startRepair(game.player, game.clothing)
    assertEqual(#game.repairs, 1, "initial repairs")

    -- The first action closes the real hole. Worn clothing can still expose
    -- its prior visual for several seconds while multiplayer sync settles.
    game.repairs[1]:complete()
    for tick = 1, 12 do
        game.getTask().think(game.getTask())
        assertEqual(#game.repairs, 1, "repairs during stale visual tick " .. tick)
        assertEqual(game.getStop(), nil, "completion during stale visual tick " .. tick)
    end

    game.settleVisual()
    game.getTask().think(game.getTask())
    game.getTask().think(game.getTask())

    assertEqual(game.getPatch(), nil, "padding patch")
    assertEqual(game.getStop().text, "UI_AA_repair_done", "completion text")
end)

run("a rejected worn repair is reported as incomplete", function()
    local game = fixture()

    AutoAll.Tailor.startRepair(game.player, game.clothing)

    -- Let the queued action drain without completing it, as happens when
    -- vanilla rejects an action after Auto All hands it over.
    for tick = 1, 20 do
        game.getTask().think(game.getTask())
        assertEqual(game.getStop(), nil, "completion before settle timeout tick " .. tick)
    end
    game.getTask().think(game.getTask())

    assertEqual(#game.repairs, 1, "repair attempts")
    assertEqual(game.getStop().text, "UI_AA_repair_partial", "completion text")
    assertEqual(game.getStop().bad, true, "completion severity")
end)

run("a carried garment still restores in one repair", function()
    local game = fixture()

    AutoAll.Tailor.startRepair(game.player, game.clothing)
    game.repairs[1]:complete()
    game.settleVisual()
    game.getTask().think(game.getTask())
    game.getTask().think(game.getTask())

    assertEqual(#game.repairs, 1, "repair attempts")
    assertEqual(game.getPatch(), nil, "padding patch")
    assertEqual(game.getStop().text, "UI_AA_repair_done", "completion text")
    assertEqual(game.getStop().bad, false, "completion severity")
end)

if failures > 0 then
    print(tostring(failures) .. " worn repair test(s) failed")
    os.exit(1)
end

print("all worn repair tests passed")
