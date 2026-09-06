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

local function vhsFixture(items, cutoff, level, recipeActuallyKnown)
    resetGlobals({ vhsBooksOnly = false, vhsNearby = false })
    local perk = { getId = function() return "Mechanics" end }
    Perks.Mechanics = perk
    SandboxVars.LevelForMediaXPCutoff = cutoff
    local mainInventory = inventory(items)
    for _, value in ipairs(items) do value.container = mainInventory end
    local player = {
        getInventory = function() return mainInventory end,
        isKnownMediaLine = function() return false end,
        getPerkLevel = function() return level end,
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

if failures > 0 then
    print(tostring(failures) .. " regression test(s) failed")
    os.exit(1)
end

print("all regression tests passed")
