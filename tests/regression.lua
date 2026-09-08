local failures = 0
local root = arg[0]:match("^(.*)/tests/regression%.lua$") or "."

local function fail(message)
    error(message, 2)
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail((message or "values differ")
                .. ": expected " .. tostring(expected)
                .. ", got " .. tostring(actual))
    end
end

local function assertNotNil(value, message)
    if value == nil then fail(message or "expected a value") end
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

    function result:isEmpty()
        return #self.values == 0
    end

    function result:contains(value)
        for _, candidate in ipairs(self.values) do
            if candidate == value then return true end
        end
        return false
    end

    function result:containsAll(other)
        for i = 0, other:size() - 1 do
            if not self:contains(other:get(i)) then return false end
        end
        return true
    end

    return result
end

local function inventory(items)
    local direct = list(items)
    local result = {}

    function result:contains(item)
        return direct:contains(item)
    end

    function result:getItemById(id)
        for _, item in ipairs(direct.values) do
            if item:getID() == id then return item end
        end
        return nil
    end

    function result:getItems()
        return direct
    end

    function result:getAllEvalRecurse(predicate, out)
        for _, item in ipairs(direct.values) do
            if predicate(item) then out:add(item) end
        end
        return out
    end

    return result
end

local function resetGlobals(options)
    options = options or {}
    local capturedTask = nil

    AutoAll = {
        opt = function(name) return options[name] end,
        enabled = function() return false end,
        holds = function() return true end,
        isQueueBusy = function() return false end,
        isRunning = function() return false end,
        reason = function() end,
        say = function() end,
        stop = function() end,
        now = function() return 0 end,
        registerMenu = function() end,
        startTask = function(task)
            capturedTask = task
            return true
        end,
        Water = {},
    }

    Events = {
        OnFillInventoryObjectContextMenu = {},
        OnGameStart = { Add = function() end },
    }
    ArrayList = { new = function() return list() end }
    ItemTag = { UNINTERESTING = "Uninteresting" }
    CharacterTrait = { DISORGANIZED = "Disorganized" }
    CharacterActionAnims = { Craft = "Craft" }
    HaloTextHelper = { addBadText = function() end }
    ISInventoryPaneContextMenu = { getContainers = function() return list() end }
    ISInventoryPane = {}
    SkillBook = {}
    Perks = {}
    SandboxVars = {}
    RWMMedia = nil
    MuscleManager = nil
    PZAPI = nil

    _G.require = function() return true end
    _G.instanceof = function(value, className)
        return value ~= nil and value.className == className
    end
    _G.getText = function(key) return key end

    return function() return capturedTask end
end

local function loadFeature(path)
    local chunk, message = loadfile(root .. "/" .. path)
    if not chunk then fail(message) end
    chunk()
end

local function item(id, fullType, container)
    local result = { id = id, fullType = fullType, container = container }
    function result:getID() return self.id end
    function result:getFullType() return self.fullType end
    function result:getDisplayName() return self.fullType end
    function result:getContainer() return self.container end
    return result
end

local function cookFixture()
    local getTask = resetGlobals({ cookBadFromLevel = 0 })
    local queued = {}

    ISTimedActionQueue = {
        add = function(action) queued[#queued + 1] = action end,
        hasAction = function() return false end,
    }
    ISInventoryTransferUtil = {
        newInventoryTransferAction = function(player, moved, source, destination)
            return {
                kind = "transfer",
                player = player,
                item = moved,
                source = source,
                destination = destination,
                setAllowMissingItems = function() end,
            }
        end,
    }
    ISAddItemInRecipe = {
        new = function(_, player, recipe, base, ingredient)
            return {
                kind = "add",
                player = player,
                recipe = recipe,
                baseItem = base,
                ingredient = ingredient,
                start = function() end,
                setActionAnim = function() end,
            }
        end,
    }
    ISTakeWaterAction = {
        new = function(_, player, base, source, tainted)
            return {
                kind = "fill",
                player = player,
                base = base,
                source = source,
                tainted = tainted,
            }
        end,
    }
    luautils = {
        walkAdjObject = function() return true end,
    }

    loadFeature("Contents/mods/AutoAll/42/media/lua/client/AutoAll/AutoAll_Cook.lua")
    return AutoAll.Cook, getTask, queued
end

run("cooking transfers a nested pot before adding an ingredient", function()
    local Cook, getTask, queued = cookFixture()
    local backpack = { name = "backpack" }
    local base = item(1, "Base.Pot", backpack)
    local ingredient = item(2, "Base.Carrot", nil)
    local mainInventory = inventory({ ingredient })
    ingredient.container = mainInventory
    local player = {
        getInventory = function() return mainInventory end,
        getUsername = function() return "player" end,
    }
    local recipe = {
        getUntranslatedName = function() return "Soup" end,
    }

    Cook.getContainers = function() return list() end
    Cook.findRecipe = function() return recipe end
    Cook.pickNext = function() return ingredient end
    Cook.canUseBadIngredients = function() return false end

    Cook.start(player, base, "Soup")
    local task = getTask()
    assertNotNil(task, "cooking task was not started")
    task.think(task)

    assertEqual(#queued, 2, "queue length")
    assertEqual(queued[1].kind, "transfer", "first action")
    assertEqual(queued[1].item, base, "transferred item")
    assertEqual(queued[2].kind, "add", "second action")
end)

run("water filling transfers a nested pot before filling it", function()
    local Cook, getTask, queued = cookFixture()
    local backpack = { name = "backpack" }
    local fluid = {
        getCapacity = function() return 1.5 end,
        getAmount = function() return 0 end,
    }
    local base = item(3, "Base.Pot", backpack)
    function base:haveExtraItems() return false end
    function base:getFluidContainer() return fluid end

    local mainInventory = inventory({})
    function mainInventory:getItemById(id)
        if id == base:getID() then return base end
        return nil
    end
    local player = {
        getInventory = function() return mainInventory end,
    }
    local recipe = {
        getUntranslatedName = function() return "Soup" end,
        getMinimumWater = function() return 0.6 end,
        hasMinimumWater = function() return false end,
    }

    Cook.findBaseRecipe = function() return recipe end
    Cook.canUseBadIngredients = function() return false end
    Cook.findWaterSource = function() return { name = "sink" }, false end

    Cook.startWater(player, base, "Soup")
    local task = getTask()
    assertNotNil(task, "water cooking task was not started")
    task.think(task)

    assertEqual(#queued, 1, "queue length")
    assertEqual(queued[1].kind, "transfer", "first action")
    assertEqual(queued[1].item, base, "transferred item")
end)

local function mediaLine(guid, codes)
    return {
        getTextGuid = function() return guid end,
        getCodes = function() return codes end,
    }
end

local function tape(id, lines)
    local media = {
        getLineCount = function() return #lines end,
        getLine = function(_, index) return lines[index + 1] end,
        getIndexForLua = function() return id + 1000 end,
    }
    local result = item(id, "Base.VHS" .. tostring(id), nil)
    result.className = "RecordedMedia"
    function result:isRecordedMedia() return true end
    function result:getMediaType() return 1 end
    function result:getMediaData() return media end
    return result
end

local function vhsFixture(items, cutoff, level, recipeActuallyKnown, booksOnly, book)
    book = book or {}
    resetGlobals({
        vhsBooksOnly = booksOnly == true,
        vhsBookXpThreshold = book.threshold,
        vhsNearby = false,
    })
    local perkName = book.perkName or "Mechanics"
    local perk = { getId = function() return perkName end }
    Perks[perkName] = perk
    SkillBook[perkName] = {
        perk = perk,
        maxMultiplier1 = book.maxMultiplier1 or 3,
        maxMultiplier2 = book.maxMultiplier2 or 5,
        maxMultiplier3 = book.maxMultiplier3 or 8,
        maxMultiplier4 = book.maxMultiplier4 or 12,
        maxMultiplier5 = book.maxMultiplier5 or 16,
    }
    SandboxVars.LevelForMediaXPCutoff = cutoff
    local mainInventory = inventory(items)
    for _, value in ipairs(items) do value.container = mainInventory end
    local player = {
        getInventory = function() return mainInventory end,
        isKnownMediaLine = function() return false end,
        getPerkLevel = function() return level end,
        getXp = function()
            return { getMultiplier = function() return book.multiplier or 0 end }
        end,
        isRecipeKnown = function(_, recipe, strict)
            if strict == true then return recipeActuallyKnown end
            return true
        end,
        isRecipeActuallyKnown = function() return recipeActuallyKnown end,
    }

    loadFeature("Contents/mods/AutoAll/42/media/lua/client/AutoAll/AutoAll_VHS.lua")
    return AutoAll.VHS, player
end

run("VHS keeps a tape with an actually unknown recipe when its skill is capped", function()
    local value = tape(10, { mediaLine("line-10", "MEC+1,RCP+Soup") })
    local VHS, player = vhsFixture({ value }, 3, 3, false)
    assertNotNil(VHS.appraise(player, value), "unknown recipe tape was rejected")
end)

run("VHS reports the configured media XP cutoff", function()
    local value = tape(11, { mediaLine("line-11", "MEC+1") })
    local VHS, player = vhsFixture({ value }, 5, 5, true)
    local found, blocked, capped = VHS.collect(player)
    assertEqual(#found, 0, "eligible tape count")
    assertEqual(blocked, 0, "book-blocked tape count")
    assertEqual(capped, 1, "capped tape count")

    local textCall = nil
    getText = function(key, ...)
        textCall = { key = key, args = { ... } }
        return key
    end
    local data = {
        getMediaType = function() return 1 end,
        getIsTurnedOn = function() return true end,
    }
    local square = { getDeviceData = function() return data end }
    VHS.start(player, { object = {}, square = square })

    assertNotNil(textCall, "no unavailable message was requested")
    assertEqual(textCall.key, "UI_AA_vhs_capped", "unavailable message")
    assertEqual(textCall.args[1], 5, "cutoff message value")
end)

run("VHS preserves the unread skill book message", function()
    local value = tape(12, { mediaLine("line-12", "MEC+1") })
    local VHS, player = vhsFixture({ value }, 5, 1, true, true)
    local found, blocked, capped = VHS.collect(player)
    assertEqual(#found, 0, "eligible tape count")
    assertEqual(blocked, 1, "book-blocked tape count")
    assertEqual(capped, 0, "capped tape count")

    local textCall = nil
    getText = function(key, ...)
        textCall = { key = key, args = { ... } }
        return key
    end
    local data = {
        getMediaType = function() return 1 end,
        getIsTurnedOn = function() return true end,
    }
    local square = { getDeviceData = function() return data end }
    VHS.start(player, { object = {}, square = square })

    assertNotNil(textCall, "no unavailable message was requested")
    assertEqual(textCall.key, "UI_AA_vhs_nobook", "unavailable message")
end)

run("VHS book gate defaults to the relevant book's full multiplier", function()
    local value = tape(13, { mediaLine("line-13", "MEC+1") })
    local VHS, player = vhsFixture({ value }, 10, 1, true, true, {
        multiplier = 2.7,
    })
    local found, blocked = VHS.collect(player)
    assertEqual(#found, 0, "eligible tape count")
    assertEqual(blocked, 1, "book-blocked tape count")
end)

run("VHS book gate stays off by default", function()
    local value = tape(14, { mediaLine("line-14", "MEC+1") })
    local VHS, player = vhsFixture({ value }, 10, 1, true, false, {
        multiplier = 0,
    })
    local found, blocked = VHS.collect(player)
    assertEqual(#found, 1, "eligible tape count")
    assertEqual(blocked, 0, "book-blocked tape count")
end)

run("VHS book gate uses the book for the current level band", function()
    local value = tape(15, { mediaLine("line-15", "MEC+1") })
    local VHS, player = vhsFixture({ value }, 10, 2, true, true, {
        multiplier = 3,
    })
    local found, blocked = VHS.collect(player)
    assertEqual(#found, 0, "eligible tape count")
    assertEqual(blocked, 1, "book-blocked tape count")
end)

run("VHS book gate accepts a configured partial multiplier threshold", function()
    local value = tape(16, { mediaLine("line-16", "MEC+1") })
    local VHS, player = vhsFixture({ value }, 10, 1, true, true, {
        multiplier = 1.5,
        threshold = 50,
    })
    local found, blocked = VHS.collect(player)
    assertEqual(#found, 1, "eligible tape count")
    assertEqual(blocked, 0, "book-blocked tape count")
end)

run("VHS book gate rejects a multiplier below the configured threshold", function()
    local value = tape(17, { mediaLine("line-17", "MEC+1") })
    local VHS, player = vhsFixture({ value }, 10, 1, true, true, {
        multiplier = 1.5,
        threshold = 60,
    })
    local found, blocked = VHS.collect(player)
    assertEqual(#found, 0, "eligible tape count")
    assertEqual(blocked, 1, "book-blocked tape count")
end)

run("VHS book gate uses the lower maximum for aiming books", function()
    local value = tape(18, { mediaLine("line-18", "AIM+1") })
    local VHS, player = vhsFixture({ value }, 10, 1, true, true, {
        perkName = "Aiming",
        multiplier = 1.5,
        maxMultiplier1 = 1.5,
        maxMultiplier2 = 2.5,
        maxMultiplier3 = 4,
        maxMultiplier4 = 6,
        maxMultiplier5 = 8,
    })
    local found, blocked = VHS.collect(player)
    assertEqual(#found, 1, "eligible tape count")
    assertEqual(blocked, 0, "book-blocked tape count")
end)

run("VHS book gate follows every two-level book band", function()
    local cases = {
        { level = 0, multiplier = 3 },
        { level = 2, multiplier = 5 },
        { level = 4, multiplier = 8 },
        { level = 6, multiplier = 12 },
        { level = 8, multiplier = 16 },
    }
    for index, case in ipairs(cases) do
        local value = tape(20 + index, { mediaLine("line-band-" .. index, "MEC+1") })
        local VHS, player = vhsFixture({ value }, 10, case.level, true, true, {
            multiplier = case.multiplier,
        })
        local found, blocked = VHS.collect(player)
        assertEqual(#found, 1, "eligible tape count for level " .. case.level)
        assertEqual(blocked, 0, "book-blocked tape count for level " .. case.level)
    end
end)

run("VHS book gate still watches tapes for skills without books", function()
    local value = tape(26, { mediaLine("line-no-book", "MEC+1") })
    local VHS, player = vhsFixture({ value }, 10, 1, true, true, {
        multiplier = 0,
    })
    SkillBook.Mechanics = nil
    local found, blocked = VHS.collect(player)
    assertEqual(#found, 1, "eligible tape count")
    assertEqual(blocked, 0, "book-blocked tape count")
end)

run("VHS book gate still watches tapes that teach unknown recipes", function()
    local value = tape(27, { mediaLine("line-recipe", "RCP=Generator") })
    local VHS, player = vhsFixture({ value }, 10, 1, false, true, {
        multiplier = 0,
    })
    local found, blocked = VHS.collect(player)
    assertEqual(#found, 1, "eligible tape count")
    assertEqual(blocked, 0, "book-blocked tape count")
end)

local function muscleFixture(part, optionOverrides)
    resetGlobals()
    local tickers = {}
    Events.OnTick = { Add = function(callback) tickers[#tickers + 1] = callback end }
    Events.OnPlayerUpdate = { Add = function() end }
    Events.OnPlayerDeath = { Add = function() end }

    local speedSlot = 1
    local multiplier = 1
    local actions = {}
    local queue = { queue = actions }

    isClient = function() return false end
    isServer = function() return false end
    getTimestampMs = function() return 0 end
    getGameSpeed = function() return speedSlot end
    setGameSpeed = function(value) speedSlot = value end
    UIManager = {
        getSpeedControls = function()
            return {
                getCurrentGameSpeed = function() return speedSlot end,
                SetCurrentGameSpeed = function(_, value) speedSlot = value end,
            }
        end,
    }
    getGameTime = function()
        return { setMultiplier = function(_, value) multiplier = value end }
    end
    ISFitnessAction = {
        stop = function() setGameSpeed(1) end,
        perform = function() setGameSpeed(1) end,
    }
    ISTimedActionQueue = {
        shouldResetGameSpeed = false,
        getTimedActionQueue = function() return queue end,
    }
    MoodleType = { HEAVY_LOAD = "heavy", ENDURANCE = "endurance", PAIN = "pain" }
    BodyPartType = { Head = "head", Torso_Upper = "upper", Torso_Lower = "lower" }

    AutoAll.enabled = function() return true end
    AutoAll.opt = function() return false end

    loadFeature("Contents/mods/AutoAll/42/media/lua/client/MuscleManager/MuscleManager_Config.lua")
    loadFeature("Contents/mods/AutoAll/42/media/lua/client/MuscleManager/MuscleManager_Core.lua")

    if optionOverrides then
        local originalOpt = MuscleManager.opt
        MuscleManager.opt = function(key)
            if optionOverrides[key] ~= nil then return optionOverrides[key] end
            return originalOpt(key)
        end
    end

    local bodyPart = part or {
        getFractureTime = function() return 0 end,
        getSplintFactor = function() return 0 end,
        isDeepWounded = function() return false end,
        stitched = function() return false end,
        getBleedingTime = function() return 0 end,
        bandaged = function() return false end,
    }
    local bodyParts = list({ bodyPart })
    local bodyDamage = {
        getOverallBodyHealth = function() return 100 end,
        getBodyParts = function() return bodyParts end,
    }
    local player = {
        getPlayerNum = function() return 0 end,
        getBodyDamage = function() return bodyDamage end,
        getVehicle = function() return nil end,
        getStats = function()
            return {
                getNumVisibleZombies = function() return 0 end,
                getNumChasingZombies = function() return 0 end,
                getNumVeryCloseZombies = function() return 0 end,
            }
        end,
        getMoodles = function()
            return { getMoodleLevel = function() return 0 end }
        end,
        isDead = function() return false end,
        pressedMovement = function() return false end,
        isAiming = function() return false end,
        pressedCancelAction = function() return false end,
    }

    return MuscleManager, player, {
        actions = actions,
        tick = function()
            for _, callback in ipairs(tickers) do callback() end
        end,
        speed = function() return speedSlot end,
        multiplier = function() return multiplier end,
        setSpeed = function(value) speedSlot = value end,
        fitnessAction = function(player)
            return setmetatable({ Type = "ISFitnessAction", character = player },
                    { __index = ISFitnessAction })
        end,
    }
end

run("Auto Exercise restores held speed after vanilla ends a fitness action", function()
    local MM, player, game = muscleFixture()
    local state = { player = player, active = true, phase = "exercising" }
    MM.states[0] = state
    local action = game.fitnessAction(player)
    game.actions[1] = action

    game.tick()
    assertEqual(game.speed(), 2, "initial held speed slot")

    action:perform()

    assertEqual(game.speed(), 2, "speed after vanilla fitness reset")
    assertEqual(state.speedGaveUp, nil, "speed ownership after vanilla reset")
end)

run("Auto Exercise restores held speed after vanilla stops a fitness action", function()
    local MM, player, game = muscleFixture()
    local state = { player = player, active = true, phase = "exercising" }
    MM.states[0] = state
    local action = game.fitnessAction(player)
    game.actions[1] = action

    game.tick()
    action:stop()

    assertEqual(game.speed(), 2, "speed after vanilla fitness stop")
    assertEqual(state.speedGaveUp, nil, "speed ownership after vanilla stop")
end)

run("Auto Exercise still respects manual 1x during a fitness action", function()
    local MM, player, game = muscleFixture()
    local state = { player = player, active = true, phase = "exercising" }
    MM.states[0] = state
    local action = game.fitnessAction(player)
    game.actions[1] = action

    game.tick()
    game.setSpeed(1)
    game.tick()
    action:perform()

    assertEqual(game.speed(), 1, "manual speed slot")
    assertEqual(state.speedGaveUp, true, "manual override latch")
end)

run("Auto Exercise preserves a manually selected fast speed across fitness completion", function()
    local MM, player, game = muscleFixture()
    local state = { player = player, active = true, phase = "exercising" }
    MM.states[0] = state
    local action = game.fitnessAction(player)
    game.actions[1] = action

    game.tick()
    game.setSpeed(3)
    game.tick()
    action:perform()

    assertEqual(game.speed(), 3, "followed speed slot")
    assertEqual(state.speedGaveUp, true, "manual override latch")
end)

run("Auto Exercise preserves a manual pause across fitness completion", function()
    local MM, player, game = muscleFixture()
    local state = { player = player, active = true, phase = "exercising" }
    MM.states[0] = state
    local action = game.fitnessAction(player)
    game.actions[1] = action

    game.tick()
    game.setSpeed(0)
    game.tick()
    action:perform()

    assertEqual(game.speed(), 0, "paused speed slot")
    assertEqual(state.speedGaveUp, true, "manual override latch")
end)

run("Auto Exercise does not restore speed after its session stops", function()
    local MM, player, game = muscleFixture()
    local state = { player = player, active = true, phase = "exercising" }
    MM.states[0] = state
    local action = game.fitnessAction(player)
    game.actions[1] = action

    game.tick()
    MM.states[0] = nil
    state.active = false
    action:perform()

    assertEqual(game.speed(), 1, "speed after stopped session")
end)

local function injuryPart(fracture, splint, deepWound, stitched, bleeding, bandaged, partType)
    return {
        getFractureTime = function() return fracture or 0 end,
        getSplintFactor = function() return splint or 0 end,
        isDeepWounded = function() return deepWound == true end,
        stitched = function() return stitched == true end,
        getBleedingTime = function() return bleeding or 0 end,
        bandaged = function() return bandaged == true end,
        getType = function() return partType or "arm" end,
    }
end

run("Auto Exercise allows a treated splinted fracture", function()
    local MM, player = muscleFixture(injuryPart(100, 1, false, false, 0, false))
    local reason = MM.checkSafety({ player = player, lastHealth = 100, setStartedAt = 0 })
    assertEqual(reason, nil, "safety stop reason")
end)

run("Auto Exercise stops for an untreated fracture by default", function()
    local MM, player = muscleFixture(injuryPart(100, 0, false, false, 0, false))
    local reason = MM.checkSafety({ player = player, lastHealth = 100, setStartedAt = 0 })
    assertEqual(reason, "UI_MM_stop_injury", "safety stop reason")
end)

run("Auto Exercise allows a fracture on a body part that cannot be splinted", function()
    local MM, player = muscleFixture(
            injuryPart(100, 0, false, false, 0, false, "head"))
    local reason = MM.checkSafety({ player = player, lastHealth = 100, setStartedAt = 0 })
    assertEqual(reason, nil, "safety stop reason")
end)

run("Auto Exercise injury safety can be switched off", function()
    local MM, player = muscleFixture(
            injuryPart(100, 0, false, false, 0, false), { stopInjury = false })
    local reason = MM.checkSafety({ player = player, lastHealth = 100, setStartedAt = 0 })
    assertEqual(reason, nil, "safety stop reason")
end)

run("Auto Exercise allows bandaged bleeding and stitched deep wounds", function()
    local treated = injuryPart(0, 0, true, true, 100, true)
    local MM, player = muscleFixture(treated)
    local reason = MM.checkSafety({ player = player, lastHealth = 100, setStartedAt = 0 })
    assertEqual(reason, nil, "safety stop reason")
end)

run("Auto Exercise stops for an unbandaged deep wound", function()
    local MM, player = muscleFixture(injuryPart(0, 0, true, false, 0, false))
    local reason = MM.checkSafety({ player = player, lastHealth = 100, setStartedAt = 0 })
    assertEqual(reason, "UI_MM_stop_injury", "safety stop reason")
end)

run("Auto Exercise stops for unbandaged active bleeding", function()
    local MM, player = muscleFixture(injuryPart(0, 0, false, false, 100, false))
    local reason = MM.checkSafety({ player = player, lastHealth = 100, setStartedAt = 0 })
    assertEqual(reason, "UI_MM_stop_injury", "safety stop reason")
end)

local function readFixture(options)
    resetGlobals(options)
    loadFeature("Contents/mods/AutoAll/42/media/lua/client/AutoAll/AutoAll_Read.lua")
    return AutoAll.Read
end

run("singleplayer skips a fully read Mechanics skill book", function()
    local Read = readFixture({ readSkillBooks = true, readMagazines = true })
    local perk = { name = "Mechanics" }
    SkillBook.Mechanics = { perk = perk }
    local book = {
        className = "Literature",
        getSkillTrained = function() return "Mechanics" end,
        getLvlSkillTrained = function() return 1 end,
        getMaxLevelTrained = function() return 2 end,
        getNumberOfPages = function() return 220 end,
        getFullType = function() return "Base.BookMechanic1" end,
        hasTag = function() return false end,
    }
    local player = {
        getPerkLevel = function() return 0 end,
        getAlreadyReadPages = function() return 220 end,
    }

    assertEqual(Read.appraise(player, book), nil, "fully read book appraisal")
end)

run("singleplayer skips an already read Mechanics magazine", function()
    local Read = readFixture({ readSkillBooks = true, readMagazines = true })
    local learned = list({ "Basic Mechanics" })
    local magazine = {
        className = "Literature",
        getSkillTrained = function() return "" end,
        getLearnedRecipes = function() return learned end,
        getFullType = function() return "Base.MechanicMag1" end,
        hasTag = function() return false end,
    }
    local player = {
        getAlreadyReadBook = function()
            return { contains = function(_, value)
                return value == "Base.MechanicMag1"
            end }
        end,
        getKnownRecipes = function()
            return { containsAll = function() return false end }
        end,
    }

    assertEqual(Read.appraise(player, magazine), nil, "already read magazine appraisal")
end)

local function safetyFixture(options, moodleLevel, health)
    resetGlobals(options)
    Events.OnPlayerUpdate = { Add = function() end }
    Events.OnPlayerDeath = { Add = function() end }
    Events.OnKeyPressed = { Add = function() end }
    Events.OnTick = { Add = function() end }

    isClient = function() return false end
    isServer = function() return false end
    getTimestampMs = function() return 0 end
    getGameSpeed = function() return 1 end
    setGameSpeed = function() end
    ISTimedActionQueue = { getTimedActionQueue = function() return nil end }
    MoodleType = { HEAVY_LOAD = "heavy" }

    loadFeature("Contents/mods/AutoAll/42/media/lua/client/AutoAll/AutoAll_Core.lua")

    local player = {
        getPlayerNum = function() return 0 end,
        isDead = function() return false end,
        getBodyDamage = function()
            return { getOverallBodyHealth = function() return health or 60 end }
        end,
        getMoodles = function()
            return { getMoodleLevel = function() return moodleLevel or 0 end }
        end,
        getStats = function()
            return {
                getNumVisibleZombies = function() return 0 end,
                getNumChasingZombies = function() return 0 end,
                getNumVeryCloseZombies = function() return 0 end,
            }
        end,
        -- Overloaded on the exact test, which is what the old rule read.
        getInventoryWeight = function() return 20 end,
        getMaxWeight = function() return 10 end,
        pressedMovement = function() return false end,
        isPlayerMoving = function() return false end,
        isAiming = function() return false end,
        pressedAim = function() return false end,
        pressedCancelAction = function() return false end,
    }

    return AutoAll, player
end

local SAFE = { stopDamage = true, healthFloor = 70 }

run("Auto Cook is not stopped for being hurt and overloaded", function()
    local AA, player = safetyFixture(SAFE, 4, 60)
    local task = { player = player, lastHealth = 60, startedAt = 0 }
    assertEqual(AA.checkSafety(task), nil, "safety stop reason")
end)

run("Auto Cook still stops when health is actually dropping", function()
    local AA, player = safetyFixture(SAFE, 4, 60)
    local task = { player = player, lastHealth = 100, startedAt = 0 }
    assertEqual(AA.checkSafety(task), "UI_AA_stop_damage", "safety stop reason")
end)

run("Auto Medicine still treats a wound that is bleeding", function()
    local AA, player = safetyFixture(SAFE, 4, 60)
    local task = {
        player = player,
        lastHealth = 100,
        startedAt = 0,
        expectedDamage = function() return true end,
    }
    assertEqual(AA.checkSafety(task), nil, "safety stop reason")
end)

run("Auto Mechanics stops below the health floor when heavily loaded", function()
    local AA, player = safetyFixture(SAFE, 4, 60)
    local task = { player = player, lastHealth = 60, startedAt = 0, ignoreDamage = true }
    assertEqual(AA.checkSafety(task), "UI_AA_stop_hurt", "safety stop reason")
end)

run("Auto Mechanics keeps working while heavily loaded and healthy", function()
    local AA, player = safetyFixture(SAFE, 4, 90)
    local task = { player = player, lastHealth = 90, startedAt = 0, ignoreDamage = true }
    assertEqual(AA.checkSafety(task), nil, "safety stop reason")
end)

run("Auto Mechanics keeps working while hurt and barely over the limit", function()
    local AA, player = safetyFixture(SAFE, 1, 60)
    local task = { player = player, lastHealth = 60, startedAt = 0, ignoreDamage = true }
    assertEqual(AA.checkSafety(task), nil, "safety stop reason")
end)

run("the health floor can be switched off without giving up stop-on-damage", function()
    local AA, player = safetyFixture({ stopDamage = true, healthFloor = 0 }, 4, 60)
    local floored = { player = player, lastHealth = 60, startedAt = 0, ignoreDamage = true }
    assertEqual(AA.checkSafety(floored), nil, "health floor stop reason")

    local hurt = { player = player, lastHealth = 100, startedAt = 0 }
    assertEqual(AA.checkSafety(hurt), "UI_AA_stop_damage", "damage stop reason")
end)

local function openFixture()
    resetGlobals()
    ItemTag.PRESERVED_FOOD = "PreservedFood"
    Events.OnFillInventoryObjectContextMenu = { Add = function() end }

    loadFeature("Contents/mods/AutoAll/42/media/lua/client/AutoAll/AutoAll_Open.lua")
    return AutoAll.Open
end

local function packaged(fullType, opening, doubleClick, tag)
    return {
        getFullType = function() return fullType end,
        getOpeningRecipe = function() return opening end,
        getDoubleClickRecipe = function() return doubleClick end,
        hasTag = function(_, wanted) return tag ~= nil and wanted == tag end,
    }
end

local function familyKey(Open, item)
    local family = Open.familyOf(item)
    return family and family.key or nil
end

run("a sealed tin still resolves to the food family", function()
    local Open = openFixture()
    local tin = packaged("Base.CannedBeans", "OpenCannedFood", nil, nil)
    assertEqual(familyKey(Open, tin), "food", "family")
end)

run("a preserved jar resolves to the food family by tag", function()
    local Open = openFixture()
    local jar = packaged("Base.JarOfPickles", nil, nil, "PreservedFood")
    assertEqual(familyKey(Open, jar), "food", "family")
end)

run("a mystery can with no opening recipe still resolves to food", function()
    local Open = openFixture()
    local can = packaged("Base.MysteryCan", nil, nil, nil)
    assertEqual(familyKey(Open, can), "food", "family")
end)

run("an ammo carton resolves to the carton family", function()
    local Open = openFixture()
    local carton = packaged("Base.Bullets9mmCarton", nil, "OpenCarton12", nil)
    assertEqual(familyKey(Open, carton), "carton", "family")
end)

run("a nails carton is in scope with the ammo cartons", function()
    local Open = openFixture()
    local carton = packaged("Base.NailsCarton", nil, "OpenCarton12", nil)
    assertEqual(familyKey(Open, carton), "carton", "family")
end)

run("a pistol ammo box resolves to the box family", function()
    local Open = openFixture()
    local box = packaged("Base.Bullets9mmBox", nil, "OpenBoxOfBullets50", nil)
    assertEqual(familyKey(Open, box), "box", "family")
end)

run("a rifle ammo box resolves to the box family", function()
    local Open = openFixture()
    local box = packaged("Base.556Box", nil, "OpenBoxOfBullets20", nil)
    assertEqual(familyKey(Open, box), "box", "family")
end)

run("a shotgun shell box resolves to the box family", function()
    local Open = openFixture()
    local box = packaged("Base.ShotgunShellsBox", nil, "OpenBoxOfShotgunShells", nil)
    assertEqual(familyKey(Open, box), "box", "family")
end)

run("a wine bottle is still left alone", function()
    local Open = openFixture()
    local wine = packaged("Base.WineBottle2", "OpenBottleOfWine", nil, nil)
    assertEqual(familyKey(Open, wine), nil, "family")
    assertEqual(Open.isCandidate(wine), false, "candidate")
end)

run("something with no opening recipe at all is not a candidate", function()
    local Open = openFixture()
    local plank = packaged("Base.Plank", nil, nil, nil)
    assertEqual(Open.isCandidate(plank), false, "candidate")
end)

run("the carton and box jobs do not borrow the tin wording", function()
    local Open = openFixture()
    local carton = Open.familyOf(packaged("Base.308Carton", nil, "OpenCarton12", nil))
    local box = Open.familyOf(packaged("Base.308Box", nil, "OpenBoxOfBullets20", nil))
    local tin = Open.familyOf(packaged("Base.CannedBeans", "OpenCannedFood", nil, nil))

    assertEqual(carton.text.stop, "UI_AA_unpack_stop", "carton stop text")
    assertEqual(box.text.stop, "UI_AA_openbox_stop", "box stop text")
    assertEqual(tin.text.stop, "UI_AA_open_stop", "tin stop text")
    -- A carton needs no tool, so that dead end must not claim one is missing.
    assertEqual(carton.text.notool, carton.text.blocked, "carton tool text")
end)

if failures > 0 then
    print(tostring(failures) .. " regression test(s) failed")
    os.exit(1)
end

print("all regression tests passed")
