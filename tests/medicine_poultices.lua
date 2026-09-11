local failures = 0
local root = arg[0]:match("^(.*)/tests/medicine_poultices%.lua$") or "."

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

    return result
end

local function makePart(overrides)
    local state = {
        injured = true,
        bandaged = false,
        bleeding = false,
        fracture = 0,
        infected = false,
        cut = false,
        scratched = false,
        deepWounded = false,
        bitten = false,
        burnt = false,
        plantain = 0,
        comfrey = 0,
        garlic = 0,
    }
    for key, value in pairs(overrides or {}) do state[key] = value end

    local part = { state = state }
    function part:HasInjury() return self.state.injured end
    function part:stitched() return false end
    function part:getSplintFactor() return 0 end
    function part:bandaged() return self.state.bandaged end
    function part:bleeding()
        if self.state.bleedingError then error("unreadable bleeding state") end
        return self.state.bleeding
    end
    function part:getBleedingTime() return self.state.bleeding and 10 or 0 end
    function part:haveBullet() return false end
    function part:haveGlass() return false end
    function part:isNeedBurnWash() return false end
    function part:getType() return "arm" end
    function part:getFractureTime() return self.state.fracture end
    function part:isInfectedWound() return self.state.infected end
    function part:isCut() return self.state.cut end
    function part:scratched() return self.state.scratched end
    function part:deepWounded() return self.state.deepWounded end
    function part:bitten() return self.state.bitten end
    function part:isBurnt() return self.state.burnt end
    function part:getPlantainFactor() return self.state.plantain end
    function part:getComfreyFactor() return self.state.comfrey end
    function part:getGarlicFactor() return self.state.garlic end
    return part
end

local function makeItem(id, itemType, bandagePower)
    local value = { id = id, itemType = itemType, bandagePower = bandagePower or 0 }
    function value:getID() return self.id end
    function value:getType() return self.itemType end
    function value:IsInventoryContainer() return false end
    function value:getBandagePower() return self.bandagePower end
    function value:isAlcoholic() return false end
    function value:hasComponent() return false end
    function value:IsDrainable() return false end
    return value
end

local function fixture(parts, items, options, outside)
    local queued = {}
    local transfers = {}
    local task
    local activeAction
    local inventoryItems = items or {}
    outside = outside or {}
    local allReachable = {}
    for _, value in ipairs(inventoryItems) do allReachable[#allReachable + 1] = value end
    for _, value in ipairs(outside or {}) do allReachable[#allReachable + 1] = value end

    local inventory = {}
    function inventory:getItems() return list(inventoryItems) end
    function inventory:containsID(id)
        return self:getItemById(id) ~= nil
    end
    function inventory:getItemById(id)
        for _, value in ipairs(inventoryItems) do
            if value:getID() == id then return value end
        end
        return nil
    end

    local player = {}
    function player:getInventory() return inventory end
    function player:getBodyDamage()
        return { getBodyParts = function() return list(parts) end }
    end
    function player:isDead() return false end
    function player:getPlayerNum() return 0 end

    AutoAll = {
        opt = function(key) return options and options[key] end,
        enabled = function() return true end,
        isQueueBusy = function() return activeAction ~= nil end,
        currentAction = function() return activeAction end,
        isRunning = function() return false end,
        addOption = function() end,
        liftOptions = function() end,
        stop = function() end,
        startTask = function(value) task = value return true end,
    }
    Events = { OnGameStart = { Add = function() end } }
    HaloTextHelper = { addGoodText = function() end }
    BodyPartType = { Head = "head", Torso_Upper = "upper", Torso_Lower = "lower" }
    ComponentType = { FluidContainer = "fluid" }
    ItemTag = {}
    ISHealthPanel = { doBodyPartContextMenu = function() end }
    ISInventoryPaneContextMenu = {
        getContainers = function()
            if #outside == 0 then return list() end
            return list({ { getItems = function() return list(outside) end } })
        end,
        transferIfNeeded = function(_, value)
            transfers[#transfers + 1] = value
        end,
    }
    ISTimedActionQueue = { add = function(action)
        queued[#queued + 1] = action
        activeAction = action
    end }

    local function actionClass(kind)
        return { new = function(_, doctor, patient, item, part)
            local action = { kind = kind, doctor = doctor, patient = patient,
                             item = item, part = part }
            function action:forceStop()
                self.stopped = true
                if activeAction == self then activeAction = nil end
            end
            return action
        end }
    end
    ISComfreyCataplasm = actionClass("comfrey")
    ISGarlicCataplasm = actionClass("garlic")
    ISPlantainCataplasm = actionClass("plantain")
    ISApplyBandage = actionClass("bandage")
    ISRemoveBullet = actionClass("bullet")
    ISRemoveGlass = actionClass("glass")
    ISCleanBurn = actionClass("burn")
    ISDisinfect = actionClass("disinfect")
    ISSplint = actionClass("splint")

    _G.require = function() return true end
    _G.getText = function(key) return key end

    local chunk, message = loadfile(root
            .. "/Contents/mods/AutoAll/42/media/lua/client/AutoAll/AutoAll_Medicine.lua")
    if not chunk then fail(message) end
    chunk()
    AutoAll.Medicine.start(player)

    return {
        player = player,
        task = function() return task end,
        queued = queued,
        transfers = transfers,
        putInInventory = function(value) inventoryItems[#inventoryItems + 1] = value end,
        finishAction = function() activeAction = nil end,
        think = function() task.think(task) end,
    }
end

local function queueFirstAction(game)
    game.think()
    game.think()
    return game.queued[1]
end

run("poultices stay off when the option is unset", function()
    local cut = makePart({ cut = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ cut }, { plantain, bandage })

    assertEqual(queueFirstAction(game).kind, "bandage", "first treatment")
end)

run("a fracture gets comfrey before its dressing", function()
    local fracture = makePart({ fracture = 20 })
    local comfrey = makeItem(1, "ComfreyCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ fracture }, { comfrey, bandage }, { medPoultices = true })

    local action = queueFirstAction(game)
    assertEqual(action.kind, "comfrey", "first treatment")
    assertEqual(action.item, comfrey, "vanilla action item")
    assertEqual(action.part, fracture, "vanilla action body part")
end)

run("an infected wound gets garlic before its dressing", function()
    local infected = makePart({ infected = true })
    local garlic = makeItem(1, "WildGarlicCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ infected }, { garlic, bandage }, { medPoultices = true })

    assertEqual(queueFirstAction(game).kind, "garlic", "first treatment")
end)

run("a cut gets plantain before its dressing", function()
    local cut = makePart({ cut = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ cut }, { plantain, bandage }, { medPoultices = true })

    assertEqual(queueFirstAction(game).kind, "plantain", "first treatment")
end)

run("a scratch gets plantain before its dressing", function()
    local scratch = makePart({ scratched = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ scratch }, { plantain, bandage }, { medPoultices = true })

    assertEqual(queueFirstAction(game).kind, "plantain", "first treatment")
end)

run("a deep wound gets plantain before its dressing", function()
    local deepWound = makePart({ deepWounded = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ deepWound }, { plantain, bandage }, { medPoultices = true })

    assertEqual(queueFirstAction(game).kind, "plantain", "first treatment")
end)

run("plantain is not spent on bites or burns it does not help", function()
    for _, injury in ipairs({ "bitten", "burnt" }) do
        local part = makePart({ [injury] = true })
        local plantain = makeItem(1, "PlantainCataplasm")
        local bandage = makeItem(2, "Bandage", 2)
        local game = fixture({ part }, { plantain, bandage }, { medPoultices = true })

        assertEqual(queueFirstAction(game).kind, "bandage", injury .. " first treatment")
    end
end)

run("any active poultice factor suppresses another poultice", function()
    for _, factor in ipairs({ "plantain", "comfrey", "garlic" }) do
        local cut = makePart({ cut = true, [factor] = 5 })
        local plantain = makeItem(1, "PlantainCataplasm")
        local bandage = makeItem(2, "Bandage", 2)
        local game = fixture({ cut }, { plantain, bandage }, { medPoultices = true })

        assertEqual(queueFirstAction(game).kind, "bandage",
                factor .. " factor first treatment")
    end
end)

run("bleeding on another open part keeps poultices behind dressings", function()
    local cut = makePart({ cut = true })
    local bleeding = makePart({ bleeding = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ cut, bleeding }, { plantain, bandage }, { medPoultices = true })

    assertEqual(queueFirstAction(game).kind, "bandage", "first treatment")
end)

run("an unreadable bleeding state fails closed for optional poultices", function()
    local cut = makePart({ cut = true })
    local unreadable = makePart({ bleedingError = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ cut, unreadable }, { plantain, bandage }, { medPoultices = true })

    assertEqual(queueFirstAction(game).kind, "bandage", "first treatment")
end)

run("bleeding that starts during a fetch cancels the poultice plan", function()
    local cut = makePart({ cut = true })
    local bleeding = makePart({ bleeding = false })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ cut, bleeding }, { bandage }, { medPoultices = true }, { plantain })

    game.think()
    assertEqual(game.transfers[1], plantain, "planned transfer")
    game.putInInventory(plantain)
    bleeding.state.bleeding = true
    game.think()
    assertEqual(#game.queued, 0, "queued treatments after bleeding starts")

    game.think()
    game.think()
    assertEqual(game.queued[1].kind, "bandage", "replacement treatment")
end)

run("bleeding after queueing cancels the poultice and resumes dressing", function()
    local cut = makePart({ cut = true })
    local bleeding = makePart({ bleeding = false })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ cut, bleeding }, { plantain, bandage }, { medPoultices = true })

    local poultice = queueFirstAction(game)
    bleeding.state.bleeding = true
    game.think()
    assertEqual(poultice.stopped, true, "queued poultice cancellation")
    assertEqual(cut.state.plantain, 0, "plantain factor after cancellation")

    game.think()
    game.think()
    local dressing = game.queued[2]
    assertEqual(dressing.kind, "bandage", "replacement treatment")
    game.think()
    assertEqual(dressing.stopped, nil, "urgent dressing cancellation")
end)

run("turning poultices off during a fetch cancels the plan", function()
    local cut = makePart({ cut = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local options = { medPoultices = true }
    local game = fixture({ cut }, { bandage }, options, { plantain })

    game.think()
    assertEqual(game.transfers[1], plantain, "planned transfer")
    game.putInInventory(plantain)
    options.medPoultices = false
    game.think()
    assertEqual(#game.queued, 0, "queued treatments after option change")

    game.think()
    game.think()
    assertEqual(game.queued[1].kind, "bandage", "replacement treatment")
end)

run("a completed poultice counts as progress and then allows dressing", function()
    local cut = makePart({ cut = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local bandage = makeItem(2, "Bandage", 2)
    local game = fixture({ cut }, { plantain, bandage }, { medPoultices = true })

    assertEqual(queueFirstAction(game).kind, "plantain", "first treatment")
    cut.state.plantain = 10
    game.finishAction()
    game.think()
    assertEqual(game.task().done, 1, "completed treatment count")
    game.think()
    assertEqual(game.queued[2].kind, "bandage", "next treatment")
end)

run("an existing dressing is never removed to apply a poultice", function()
    local cut = makePart({ cut = true, bandaged = true })
    local plantain = makeItem(1, "PlantainCataplasm")
    local game = fixture({ cut }, { plantain }, { medPoultices = true })

    assertEqual(AutoAll.Medicine.countWork(game.player), 0, "work behind dressing")
    assertEqual(#game.queued, 0, "queued treatments")
end)

if failures > 0 then
    error(tostring(failures) .. " medicine poultice test(s) failed")
end

print("all medicine poultice tests passed")
