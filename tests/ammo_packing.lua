local failures = 0
local root = arg[0]:match("^(.*)/tests/ammo_packing%.lua$") or "."

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

local function assertTrue(value, message)
    if value ~= true then fail(message or "expected true") end
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

local function inventory(items)
    local result = { direct = items or {} }

    function result:getItems()
        return list(self.direct)
    end

    function result:getAllEvalRecurse(predicate, out)
        local function visit(values)
            for _, value in ipairs(values) do
                if predicate(value) then out:add(value) end
                if value.inventory then visit(value.inventory.direct) end
            end
        end
        visit(self.direct)
        return out
    end

    return result
end

local nextId = 0

local function makeItem(fullType, container, kind)
    nextId = nextId + 1
    local value = {
        id = nextId,
        fullType = fullType,
        container = container,
        kind = kind,
    }

    function value:getID() return self.id end
    function value:getFullType() return self.fullType end
    function value:getDisplayName() return self.fullType end
    function value:getContainer() return self.container end
    function value:getOpeningRecipe() return nil end
    function value:getDoubleClickRecipe()
        if self.kind == "box" then
            if self.fullType == "Base.ShotgunShellsBox" then return "OpenBoxOfShotgunShells" end
            if self.fullType == "Base.308Box" or self.fullType == "Base.556Box"
                    or self.fullType == "Base.3030Box" or self.fullType == "Base.Bullets44Box" then
                return "OpenBoxOfBullets20"
            end
            return "OpenBoxOfBullets50"
        end
        return nil
    end
    function value:hasTag(tag)
        return self.kind == "round" and tag == "Ammo"
    end

    return value
end

local REQUIRED = {
    ["Base.Bullets44"] = 20,
    ["Base.308Bullets"] = 20,
    ["Base.ShotgunShells"] = 25,
    ["Base.556Bullets"] = 20,
    ["Base.Bullets9mm"] = 50,
    ["Base.Bullets45"] = 50,
    ["Base.Bullets38"] = 50,
    ["Base.Bullets357"] = 50,
    ["Base.3030Bullets"] = 20,
    ["Base.Bullets44Box"] = 12,
    ["Base.308Box"] = 12,
    ["Base.ShotgunShellsBox"] = 12,
    ["Base.556Box"] = 12,
    ["Base.Bullets9mmBox"] = 12,
    ["Base.Bullets45Box"] = 12,
    ["Base.Bullets38Box"] = 12,
    ["Base.Bullets357Box"] = 12,
    ["Base.3030Box"] = 12,
}

local function fixture(mainItems, nearby, options)
    local main = inventory(mainItems)
    nearby = nearby or {}
    local containers = { main }
    for _, value in ipairs(nearby) do containers[#containers + 1] = value end

    local task = nil
    local crafts = {}
    local transfers = {}
    local menuHandler = nil
    local stopped = nil

    local player = {
        getInventory = function() return main end,
        getPlayerNum = function() return 0 end,
        isDead = function() return false end,
    }

    for _, value in ipairs(mainItems) do
        if not value.container then value.container = main end
    end

    local function reachableCount(fullType)
        local seen = {}
        local total = 0
        local function consider(value)
            if not seen[value] then
                seen[value] = true
                if value:getContainer() and value:getFullType() == fullType then total = total + 1 end
            end
            return false
        end
        for _, source in ipairs(containers) do
            source:getAllEvalRecurse(consider, list())
        end
        return total
    end

    local ammoRecipe = { getName = function() return "place_ammo_in_box" end }
    local boxRecipe = { getName = function() return "Place12BoxesInCarton" end }

    options = options or {}

    AutoAll = {
        opt = function(name)
            if name == "openMax" then return options.openMax or 0 end
            return false
        end,
        addOption = function(context, label, optionPlayer, callback, args)
            local option = { label = label, player = optionPlayer, callback = callback, args = args }
            context.options[#context.options + 1] = option
            return option
        end,
        registerMenu = function(_, _, handler) menuHandler = handler end,
        startTask = function(value) task = value return true end,
        stop = function(_, text, bad) stopped = { text = text, bad = bad } end,
        isQueueBusy = function() return false end,
        isRunning = function() return false end,
        batchSize = function() return nil end,
        batchFeedback = function() end,
        reason = function() end,
    }

    Events = { OnFillInventoryObjectContextMenu = {} }
    ArrayList = { new = function() return list() end }
    ItemTag = { PRESERVED_FOOD = "PreservedFood", AMMO = "Ammo" }
    HaloTextHelper = { addBadText = function() end }
    ISInventoryPane = { getActualItems = function(values) return values end }
    ISInventoryPaneContextMenu = {
        getContainers = function() return list(containers) end,
        addToolTip = function() return {} end,
        transferIfNeeded = function(_, value)
            transfers[#transfers + 1] = value
        end,
        OnNewCraft = function(value, recipe)
            crafts[#crafts + 1] = { item = value, recipe = recipe }
        end,
    }
    ISCraftingUI = { ReturnItemToOriginalContainer = function() end }
    ISTimedActionQueue = { add = function() end }
    ISInventoryTransferAction = { new = function() return {} end }
    CraftRecipeManager = {
        getUniqueRecipeItems = function(value)
            if value.kind == "round" then return list({ ammoRecipe }) end
            if value.kind == "box" then return list({ boxRecipe }) end
            return list()
        end,
    }
    HandcraftLogic = {
        new = function()
            local logic = { selected = nil }
            function logic:findCraftSurface() return nil end
            function logic:setIsoObject() end
            function logic:setContainers() end
            function logic:setRecipeFromContextClick(_, selected) self.selected = selected end
            function logic:getPossibleCraftCount()
                local required = self.selected and REQUIRED[self.selected:getFullType()]
                if not required then return 0 end
                return math.floor(reachableCount(self.selected:getFullType()) / required)
            end
            function logic:canPerformCurrentRecipe() return self:getPossibleCraftCount() > 0 end
            function logic:getRecipeData()
                return { getAllPutBackInputItems = function() return list() end }
            end
            return logic
        end,
    }

    _G.require = function() return true end
    _G.instanceof = function(value, className)
        return className == "InventoryItem" and value ~= nil and value.getFullType ~= nil
    end
    _G.getSpecificPlayer = function() return player end
    _G.getText = function(key) return key end
    _G.isClient = function() return false end

    local chunk, message = loadfile(root
            .. "/Contents/mods/AutoAll/42/media/lua/client/AutoAll/AutoAll_Open.lua")
    if not chunk then fail(message) end
    chunk()

    return {
        Open = AutoAll.Open,
        player = player,
        main = main,
        containers = containers,
        getTask = function() return task end,
        crafts = crafts,
        transfers = transfers,
        getMenu = function() return menuHandler end,
        getStopped = function() return stopped end,
    }
end

local function makeMany(fullType, amount, container, kind)
    local values = {}
    for _ = 1, amount do values[#values + 1] = makeItem(fullType, container, kind) end
    return values
end

local function append(target, values)
    for _, value in ipairs(values) do target[#target + 1] = value end
end

local function consumeBatch(env)
    local consumed = env.getTask().items
    local removed = {}
    for _, value in ipairs(consumed) do
        value.container = nil
        removed[value] = true
    end

    local kept = {}
    for _, value in ipairs(env.main.direct) do
        if not removed[value] then kept[#kept + 1] = value end
    end
    env.main.direct = kept
end

run("loose ammo offers the separate Pack All Ammo action", function()
    local rounds = makeMany("Base.Bullets9mm", 50, nil, "round")
    local env = fixture(rounds)
    local context = { options = {} }

    env.getMenu()(0, context, { rounds[1] })

    local found = false
    for _, option in ipairs(context.options) do
        if option.label == "UI_AA_packammo_option_all" then found = true end
    end
    assertTrue(found, "Pack All Ammo menu action")
end)

run("ammo boxes offer packing without replacing their open actions", function()
    local boxes = makeMany("Base.Bullets9mmBox", 12, nil, "box")
    local env = fixture(boxes)
    local context = { options = {} }

    env.getMenu()(0, context, { boxes[1] })

    local openFound = false
    local packFound = false
    for _, option in ipairs(context.options) do
        if option.label == "UI_AA_openbox_option_all" then openFound = true end
        if option.label == "UI_AA_packboxes_option_all" then packFound = true end
    end
    assertTrue(openFound, "Open Every Box menu action")
    assertTrue(packFound, "Pack All Ammo Boxes menu action")
end)

run("every vanilla ammo type uses its recipe batch quantity", function()
    local cases = {
        { "Base.Bullets44", 20 },
        { "Base.308Bullets", 20 },
        { "Base.ShotgunShells", 25 },
        { "Base.556Bullets", 20 },
        { "Base.Bullets9mm", 50 },
        { "Base.Bullets45", 50 },
        { "Base.Bullets38", 50 },
        { "Base.Bullets357", 50 },
        { "Base.3030Bullets", 20 },
    }

    for _, case in ipairs(cases) do
        local exact = makeMany(case[1], case[2], nil, "round")
        local exactEnv = fixture(exact)
        local exactFamily = exactEnv.Open.packingFamilyOf(exact[1])
        local exactDoable = exactEnv.Open.countDoable(exactEnv.player, nil, exactFamily)
        assertEqual(exactDoable, 1, case[1] .. " exact batch")
        exactEnv.Open.start(exactEnv.player, nil, "ammo batches", nil, "packAmmo")
        assertEqual(#exactEnv.getTask().items, case[2], case[1] .. " planned inputs")

        local short = makeMany(case[1], case[2] - 1, nil, "round")
        local shortEnv = fixture(short)
        local shortFamily = shortEnv.Open.packingFamilyOf(short[1])
        local shortDoable = shortEnv.Open.countDoable(shortEnv.player, nil, shortFamily)
        assertEqual(shortDoable, 0, case[1] .. " incomplete batch")
    end
end)

run("only vanilla ammo boxes pack in matching sets of twelve", function()
    local boxTypes = {
        "Base.Bullets44Box",
        "Base.308Box",
        "Base.ShotgunShellsBox",
        "Base.556Box",
        "Base.Bullets9mmBox",
        "Base.Bullets45Box",
        "Base.Bullets38Box",
        "Base.Bullets357Box",
        "Base.3030Box",
    }

    for _, boxType in ipairs(boxTypes) do
        local boxes = makeMany(boxType, 12, nil, "box")
        local env = fixture(boxes)
        local family = env.Open.packingFamilyOf(boxes[1])
        assertEqual(family and family.key, "packBoxes", boxType .. " family")
        env.Open.start(env.player, nil, "sets of ammo boxes", nil, "packBoxes")
        assertEqual(#env.getTask().items, 12, boxType .. " planned inputs")
    end

    local nails = makeItem("Base.NailsBox", nil, "box")
    local nailsEnv = fixture({ nails })
    assertEqual(nailsEnv.Open.packingFamilyOf(nails), nil, "nails box packing family")
end)

run("round packing counts complete matching batches without mixing calibres", function()
    local items = {}
    append(items, makeMany("Base.Bullets9mm", 55, nil, "round"))
    append(items, makeMany("Base.308Bullets", 21, nil, "round"))
    local env = fixture(items)
    local family = env.Open.packingFamilyOf(items[1])

    local doable, total = env.Open.countDoable(env.player, nil, family)

    assertEqual(family.key, "packAmmo", "packing family")
    assertEqual(doable, 2, "complete batches")
    assertEqual(total, 76, "candidate rounds")
end)

run("round packing queues one homogeneous vanilla craft at a time", function()
    local items = {}
    append(items, makeMany("Base.Bullets9mm", 50, nil, "round"))
    append(items, makeMany("Base.308Bullets", 20, nil, "round"))
    append(items, makeMany("Base.Bullets9mmBox", 12, nil, "box"))
    local env = fixture(items)

    env.Open.start(env.player, nil, "ammo batches", nil, "packAmmo")

    assertEqual(#env.crafts, 1, "initial crafts")
    assertEqual(env.crafts[1].recipe:getName(), "place_ammo_in_box", "recipe")
    assertEqual(env.getTask().items[1]:getFullType(), "Base.Bullets9mm", "first calibre")
    assertEqual(#env.getTask().items, 50, "first batch size")

    consumeBatch(env)
    env.getTask().think(env.getTask())

    assertEqual(#env.crafts, 2, "crafts after replanning")
    assertEqual(env.getTask().items[1]:getFullType(), "Base.308Bullets", "second calibre")
    assertEqual(#env.getTask().items, 20, "second batch size")
end)

run("round packing leaves an incomplete quantity loose", function()
    local rounds = makeMany("Base.Bullets9mm", 51, nil, "round")
    local env = fixture(rounds)

    env.Open.start(env.player, nil, "ammo batches", nil, "packAmmo")
    consumeBatch(env)
    env.getTask().think(env.getTask())

    assertEqual(#env.crafts, 1, "craft count")
    assertEqual(#env.main.direct, 1, "loose remainder")
    assertEqual(env.main.direct[1]:getFullType(), "Base.Bullets9mm", "remainder type")
end)

run("round packing finishes every initial batch beyond the safety minimum", function()
    local rounds = makeMany("Base.308Bullets", 6040, nil, "round")
    local env = fixture(rounds)

    env.Open.start(env.player, nil, "ammo batches", nil, "packAmmo")
    while #env.crafts < 302 do
        consumeBatch(env)
        env.getTask().think(env.getTask())
        if env.getStopped() then break end
    end

    assertEqual(#env.crafts, 302, "all initial crafts")
end)

run("packing reports completion after leaving a partial batch", function()
    local rounds = makeMany("Base.Bullets9mm", 51, nil, "round")
    local env = fixture(rounds)

    env.Open.start(env.player, nil, "ammo batches", nil, "packAmmo")
    consumeBatch(env)
    env.getTask().think(env.getTask())
    env.getTask().think(env.getTask())
    env.getTask().think(env.getTask())

    assertEqual(env.getStopped().text, "UI_AA_pack_done", "completion text")
    assertEqual(env.getStopped().bad, false, "completion status")
end)

run("the packing cap counts completed crafts rather than failed attempts", function()
    local rounds = makeMany("Base.Bullets9mm", 50, nil, "round")
    local env = fixture(rounds, nil, { openMax = 1 })

    env.Open.start(env.player, nil, "ammo batches", nil, "packAmmo")
    env.getTask().think(env.getTask())

    assertEqual(#env.crafts, 2, "retried craft")
end)

run("box packing consumes only complete sets of twelve matching boxes", function()
    local items = {}
    append(items, makeMany("Base.Bullets9mmBox", 13, nil, "box"))
    append(items, makeMany("Base.308Box", 11, nil, "box"))
    local env = fixture(items)

    env.Open.start(env.player, nil, "sets of ammo boxes", nil, "packBoxes")

    assertEqual(#env.crafts, 1, "carton crafts")
    assertEqual(env.crafts[1].recipe:getName(), "Place12BoxesInCarton", "recipe")
    assertEqual(#env.getTask().items, 12, "box batch size")
    for _, value in ipairs(env.getTask().items) do
        assertEqual(value:getFullType(), "Base.Bullets9mmBox", "box type")
    end

    consumeBatch(env)
    env.getTask().think(env.getTask())
    assertEqual(#env.crafts, 1, "no mixed carton craft")
    assertEqual(#env.main.direct, 12, "unpacked remainder count")
end)

run("packing gathers one complete batch from inventory bags and nearby containers", function()
    local mainItems = makeMany("Base.Bullets9mm", 10, nil, "round")
    local bagInventory = inventory(makeMany("Base.Bullets9mm", 20, nil, "round"))
    local bag = makeItem("Base.Bag_NormalHikingBag", nil, "bag")
    bag.inventory = bagInventory
    bag.container = nil
    mainItems[#mainItems + 1] = bag
    for _, value in ipairs(bagInventory.direct) do value.container = bagInventory end

    local crate = inventory(makeMany("Base.Bullets9mm", 20, nil, "round"))
    for _, value in ipairs(crate.direct) do value.container = crate end
    local env = fixture(mainItems, { bagInventory, crate })

    env.Open.start(env.player, nil, "ammo batches", nil, "packAmmo")

    assertEqual(#env.getTask().items, 50, "gathered batch")
    assertEqual(#env.transfers, 40, "nested and nearby transfers")
    assertEqual(#env.crafts, 0, "craft waits for gathering")

    for _, value in ipairs(env.getTask().items) do value.container = env.main end
    env.getTask().think(env.getTask())
    assertEqual(#env.crafts, 1, "craft after gathering")
end)

if failures > 0 then
    print(tostring(failures) .. " ammo packing test(s) failed")
    os.exit(1)
end

print("all ammo packing tests passed")
