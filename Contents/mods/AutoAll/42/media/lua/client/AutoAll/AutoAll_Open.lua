--[[
    Auto All - Open what is sealed (Build 42 / SP + MP)
    ------------------------------------------------------------------
    "Open Every Can and Jar", on any sealed tin or preserved jar.
    "Unpack Every Carton" and "Open Every Box", on ammunition and on the
    nails and screws that share its packaging. In your inventory or
    sitting in a container you have open, either way.

    > *Dodo31320:* "Option to open canned / jarred food for cooking
    > recipes?"

    Opening one tin is two clicks. Opening the twenty a cooked meal is
    made of, one at a time, before Auto Cook can even see them, is the
    exact busywork this mod exists to remove.

    ------------------------------------------------------------------
    What counts as openable

    Three families, defined in the FAMILIES table below. Food is where
    this module started, and it is eight vanilla recipes, all
    `category = Cooking`:

      OpenCannedFood / ...WithKnifeOrSharpStoneFlake  the labelled tins
      OpenCannedFood2                                 corned beef, sardines
      OpenJarOfFood                                   everything preserved
      OpenUnlabeledCan / OpenDentedUnlabeledCan       the mystery tins
      OpenWaterRationCan                              plus knife variants

    Read from `recipes_cannedFood.txt` and `recipes_jarring.txt`. Three
    facts about them are worth writing down, because two of them are not
    what an earlier note in this file's history assumed:

    * `OpenCannedFood`, `OpenCannedFood2` and `OpenJarOfFood` have real
      `outputs` blocks driven by an `itemMapper`, so what comes out is
      decided by the script and can be planned for. Only the mystery,
      dented and water-ration recipes have empty outputs and settle it
      in Java (`RecipeCodeOnCreate.openMysteryCan`).

    * `OnCreate = RecipeCodeOnCreate.openAndEat` does NOT eat the food.
      Its first instruction is `getEatPercentage() <= 0 -> return`, and
      a plain craft carries no eat percentage; that branch only fires
      for vanilla's own "Open and Eat" entry. The tin is opened and left
      alone, which is what a cook wants.

    * Wine and beer bottles also carry an `OpeningRecipe`
      (`OpenBottleOfWine`, `OpenBottleOfBeer`). They are deliberately
      NOT in the list below - "open every can" should not go through
      the drinks cabinet.

    The other two families are packaging, and the game keeps their
    recipe on `DoubleClickRecipe` rather than `OpeningRecipe`:

      OpenCarton12            every ammo carton, and nails and screws
      OpenBoxOfBullets50      9mm, .45, .38, .357
      OpenBoxOfBullets20      .44, .308, 5.56, .30-30
      OpenBoxOfShotgunShells  shells
      OpenBox100              nails, screws, cap gun caps

    Read from `recipes_ammunition.txt` and `recipes_packing.txt`. Two
    facts about those are worth writing down:

    * They need no tool. Every one is `InHandCraft` with no tool input,
      so the "no can opener within reach" dead end cannot happen and
      those families point that message somewhere honest instead.

    * Opening ammunition makes you HEAVIER. A 9mm carton is 8.0, its
      twelve boxes are 9.6, and those as loose rounds are 12.0. That is
      why the carton and the box are two menu entries rather than one
      cascade: going all the way down is a decision rather than a
      default, and the two run in sequence for anyone who wants it.

    ------------------------------------------------------------------
    Why this runs in two phases

    The same reason Auto Sterilize and Auto Dismantle do, and the note
    at the top of AutoAll_Sterilize.lua is the long version:
    ISInventoryPaneContextMenu.OnNewCraft ends by carrying every
    borrowed input back to the container it came from, decided at queue
    time. Called once per tin with the can opener in a kitchen drawer,
    the character walks to the drawer and back once per tin.

    So the job gathers first and crafts second: phase one queues the
    transfers, phase two waits for the queue to drain and only then
    queues the crafts, by which point `returnToContainer` is empty.

    > This is the third module with that engine in it, and the note in
    > AutoAll.md says a third copy should be an extraction into
    > AutoAll_Core instead. It is not one here, deliberately: the other
    > two are running on live servers and were each fixed the hard way,
    > and rewriting them in the same round that adds a new module would
    > put three things at risk to tidy one. The extraction is still the
    > right next step - this file is written to be one of its callers.
]]

require "AutoAll/AutoAll_Core"

AutoAll = AutoAll or {}
local AA = AutoAll

if AA.openLoaded then return end
AA.openLoaded = true

AA.Open = AA.Open or {}
local Open = AA.Open

---------------------------------------------------------------------
-- three families, one engine
--
-- A family answers three questions about an item and nothing else:
-- what opens it, how to recognise it cheaply, and what the messages
-- call it. Everything below this table - gathering, the two phase
-- craft, batching, putting the results away - never asks which family
-- it is holding.
--
-- Recipes are matched by NAME rather than by item type, so a modded tin
-- or a modded ammo box that reuses a vanilla recipe is picked up for
-- free and nothing here has to track vanilla's item list.
--
-- The cheap pre-filter differs per family because the game stores the
-- association in two different places: food carries OpeningRecipe,
-- packaging carries DoubleClickRecipe. Both are plain recipe-name
-- strings read straight off the item, and reading one costs nothing
-- next to asking the crafting engine. That is what keeps the cost off
-- every right click that lands on something else.
---------------------------------------------------------------------

local function openingRecipeOf(item)
    return item:getOpeningRecipe()
end

local function doubleClickRecipeOf(item)
    return item:getDoubleClickRecipe()
end

local AMMO_BATCHES = {
    ["Base.Bullets44"]     = 20,
    ["Base.308Bullets"]    = 20,
    ["Base.ShotgunShells"] = 25,
    ["Base.556Bullets"]    = 20,
    ["Base.Bullets9mm"]    = 50,
    ["Base.Bullets45"]     = 50,
    ["Base.Bullets38"]     = 50,
    ["Base.Bullets357"]    = 50,
    ["Base.3030Bullets"]   = 20,
}

local AMMO_BOX_BATCHES = {
    ["Base.Bullets44Box"]     = 12,
    ["Base.308Box"]           = 12,
    ["Base.ShotgunShellsBox"] = 12,
    ["Base.556Box"]           = 12,
    ["Base.Bullets9mmBox"]    = 12,
    ["Base.Bullets45Box"]     = 12,
    ["Base.Bullets38Box"]     = 12,
    ["Base.Bullets357Box"]    = 12,
    ["Base.3030Box"]          = 12,
}

local FAMILIES = {
    -- The sealed tins and preserved jars this module started as. Ten
    -- recipe names, all category = Cooking, from recipes_cannedFood.txt
    -- and recipes_jarring.txt.
    food = {
        key   = "food",
        named = openingRecipeOf,
        recipes = {
            "OpenCannedFood",
            "OpenCannedFood2",
            "OpenCannedFoodWithKnifeOrSharpStoneFlake",
            "OpenJarOfFood",
            "OpenUnlabeledCan",
            "OpenUnlabeledCanWithKnifeOrSharpStoneFlake",
            "OpenDentedUnlabeledCan",
            "OpenDentedUnlabeledCanWithKnifeOrSharpStoneFlake",
            "OpenWaterRationCan",
            "OpenWaterRationCanWithKnifeOrSharpStoneFlake",
        },
        -- The tins whose script carries no OpeningRecipe line. Everything
        -- else either names its recipe (the sixteen labelled tins, corned
        -- beef and sardines) or carries base:preservedfood (every jar).
        extraTypes = {
            ["Base.MysteryCan"]      = true,
            ["Base.DentedCan"]       = true,
            ["Base.WaterRationCan"]  = true,
        },
        tag = ItemTag and ItemTag.PRESERVED_FOOD or nil,
        text = {
            option    = "UI_AA_open_option",
            optionAll = "UI_AA_open_option_all",
            labelAll  = "UI_AA_open_label_all",
            optionTt  = "UI_AA_open_option_tt",
            started   = "UI_AA_open_started",
            working   = "UI_AA_open_working",
            done      = "UI_AA_open_done",
            nothing   = "UI_AA_open_nothing",
            notool    = "UI_AA_open_notool",
            blocked   = "UI_AA_open_blocked",
            stop      = "UI_AA_open_stop",
        },
    },

    -- A carton of twelve.
    --
    -- > *Anwmalos:* "Are you planning to add ammo/ammo boxes/cartons to
    -- > this compendium?"
    --
    -- One recipe covers every one of them. OpenCarton12 takes the nine
    -- ammo cartons and the nails and screws cartons together, through a
    -- single itemMapper, so splitting ammo out would mean keeping an item
    -- list against a recipe that does not have one. They are all in.
    carton = {
        key     = "carton",
        named   = doubleClickRecipeOf,
        recipes = { "OpenCarton12" },
        text = {
            option    = "UI_AA_unpack_option",
            optionAll = "UI_AA_unpack_option_all",
            labelAll  = "UI_AA_unpack_label_all",
            optionTt  = "UI_AA_unpack_option_tt",
            started   = "UI_AA_unpack_started",
            working   = "UI_AA_unpack_working",
            done      = "UI_AA_unpack_done",
            nothing   = "UI_AA_unpack_nothing",
            -- No tool opens a carton, so the two dead ends read the same.
            notool    = "UI_AA_unpack_blocked",
            blocked   = "UI_AA_unpack_blocked",
            stop      = "UI_AA_unpack_stop",
        },
    },

    -- A box. Fifty rounds for the pistol calibres, twenty for the rifle
    -- ones, shells, and OpenBox100 for the nails, screws and cap gun
    -- caps the cartons above unpack into.
    --
    -- Deliberately a second entry rather than the tail of one cascade. A
    -- carton opened all the way down is 600 loose rounds and half again
    -- the weight it started at, which is a choice rather than a default.
    -- Running both entries in turn still gets there.
    box = {
        key   = "box",
        named = doubleClickRecipeOf,
        recipes = {
            "OpenBoxOfBullets50",
            "OpenBoxOfBullets20",
            "OpenBoxOfShotgunShells",
            "OpenBox100",
        },
        text = {
            option    = "UI_AA_openbox_option",
            optionAll = "UI_AA_openbox_option_all",
            labelAll  = "UI_AA_openbox_label_all",
            optionTt  = "UI_AA_openbox_option_tt",
            started   = "UI_AA_openbox_started",
            working   = "UI_AA_openbox_working",
            done      = "UI_AA_openbox_done",
            nothing   = "UI_AA_openbox_nothing",
            notool    = "UI_AA_openbox_blocked",
            blocked   = "UI_AA_openbox_blocked",
            stop      = "UI_AA_openbox_stop",
        },
    },

    packAmmo = {
        key        = "packAmmo",
        recipes    = { "place_ammo_in_box" },
        batchSizes = AMMO_BATCHES,
        text = {
            option    = "UI_AA_packammo_option_all",
            optionAll = "UI_AA_packammo_option_all",
            labelAll  = "UI_AA_packammo_label_all",
            optionTt  = "UI_AA_packammo_option_tt",
            started   = "UI_AA_pack_started",
            working   = "UI_AA_pack_working",
            done      = "UI_AA_pack_done",
            nothing   = "UI_AA_pack_nothing",
            notool    = "UI_AA_pack_blocked",
            blocked   = "UI_AA_pack_blocked",
            stop      = "UI_AA_pack_stop",
        },
    },

    packBoxes = {
        key        = "packBoxes",
        recipes    = { "Place12BoxesInCarton" },
        batchSizes = AMMO_BOX_BATCHES,
        text = {
            option    = "UI_AA_packboxes_option_all",
            optionAll = "UI_AA_packboxes_option_all",
            labelAll  = "UI_AA_packboxes_label_all",
            optionTt  = "UI_AA_packboxes_option_tt",
            started   = "UI_AA_pack_started",
            working   = "UI_AA_pack_working",
            done      = "UI_AA_pack_done",
            nothing   = "UI_AA_pack_nothing",
            notool    = "UI_AA_pack_blocked",
            blocked   = "UI_AA_pack_blocked",
            stop      = "UI_AA_pack_stop",
        },
    },
}

-- Ordered, so a right click resolves to exactly one family and the menu
-- is built the same way every time.
local FAMILY_ORDER = { "food", "carton", "box" }
local PACKING_ORDER = { "packAmmo", "packBoxes" }

for _, name in ipairs({ "food", "carton", "box", "packAmmo", "packBoxes" }) do
    local family = FAMILIES[name]
    family.wanted = {}
    for _, recipe in ipairs(family.recipes) do family.wanted[recipe] = true end
end

---------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------

-- Answers from CraftRecipeManager and from getContainers, held for the
-- length of one menu build or one round. Straight from Auto Dismantle,
-- and for the same reason: getUniqueRecipeItems resolves every in-hand
-- and any-surface recipe against the item, and calling it once per thing
-- in a stocked base is what froze the game on right click.
local cache = nil
local cachedContainers = nil

local function containersOf(player)
    if cache then
        if not cachedContainers then
            cachedContainers = ISInventoryPaneContextMenu.getContainers(player) or ArrayList.new()
        end
        return cachedContainers
    end
    return ISInventoryPaneContextMenu.getContainers(player) or ArrayList.new()
end

-- Counted rather than a plain flag: the menu handler opens a cache and
-- then calls countDoable twice, and countDoable has to work on its own
-- as well. Without the depth the first inner endCache would throw away
-- the outer cache and the second entry would pay full price again.
local cacheDepth = 0

local function beginCache()
    cacheDepth = cacheDepth + 1
    if cacheDepth == 1 then
        cache = {}
        cachedContainers = nil
    end
end

local function endCache()
    cacheDepth = cacheDepth - 1
    if cacheDepth <= 0 then
        cacheDepth = 0
        cache = nil
        cachedContainers = nil
    end
end

--- Runs fn inside a cache and closes the cache whatever happens.
---
--- Every caller used to do begin/work/end by hand, and an error in the
--- middle - a menu handler is already inside a pcall, so it would not
--- even be noticed - left the depth above zero and the stale cache in
--- place for the rest of the session. Wrong recipes, permanently.
local function withCache(fn, a, b, c)
    beginCache()
    local ok, first, second = pcall(fn, a, b, c)
    endCache()
    if not ok then
        print("[AutoAll] open: " .. tostring(first))
        return nil
    end
    return first, second
end

--- Cheap pre-filter: could this item plausibly be a sealed tin or jar?
---
--- Three script-level facts, none of which cost anything to read:
--- the item names its own opening recipe, or it carries the
--- base:preservedfood tag, or it is one of the three unlabelled tins
--- that do neither.
---
--- Only ever used to narrow "everything within reach" before the
--- crafting engine is asked. The engine still has the final say.
local function matchesFamily(item, family)
    if family.batchSizes and family.batchSizes[item:getFullType()] then return true end

    if family.named then
        local ok, named = pcall(family.named, item)
        if ok and type(named) == "string" and family.wanted[named] then return true end
    end

    if family.tag then
        local okTag, tagged = pcall(function() return item:hasTag(family.tag) end)
        if okTag and tagged == true then return true end
    end

    return family.extraTypes ~= nil
            and family.extraTypes[item:getFullType()] == true
end

--- Which family this item belongs to, or nil when it is not one of ours.
function Open.familyOf(item)
    if not item then return nil end

    for _, name in ipairs(FAMILY_ORDER) do
        local family = FAMILIES[name]
        if matchesFamily(item, family) then return family end
    end

    return nil
end

function Open.packingFamilyOf(item)
    if not item then return nil end

    for _, name in ipairs(PACKING_ORDER) do
        local family = FAMILIES[name]
        if matchesFamily(item, family) then return family end
    end

    return nil
end

--- Kept as a boolean because the menu guard only asks whether the click
--- landed on something this module opens at all.
function Open.isCandidate(item)
    return Open.familyOf(item) ~= nil
end

--- The opening recipe for this item, if the game will give us one.
---
--- Asked of the game rather than matched against a type list, exactly
--- as Auto Dismantle does, so the answer accounts for whether a can
--- opener or a sharp knife is actually within reach.
---
--- Cached by item type while a cache is open: which recipe applies
--- depends on the type and on the tools in reach, and neither changes
--- inside one menu build.
local function recipeFor(player, item, containers, family)
    local key = cache and item:getFullType()
    if key then
        local hit = cache[key]
        if hit ~= nil then
            if hit == false then return nil end
            return hit
        end
    end

    local available = CraftRecipeManager.getUniqueRecipeItems(item, player, containers)
    if not available then
        if key then cache[key] = false end
        return nil
    end

    for i = 0, available:size() - 1 do
        local recipe = available:get(i)
        local name = recipe:getName()
        -- Matched loosely: depending on the build getName() may or may
        -- not carry the module prefix.
        for _, wanted in ipairs(family.recipes) do
            if name == wanted or string.find(name, wanted, 1, true) then
                if key then cache[key] = recipe end
                return recipe
            end
        end
    end

    if key then cache[key] = false end
    return nil
end

--- True for an item still on a dead body.
---
--- Straight from Dismantle.onCorpse, and here for the same reason: a
--- container's parent is what says whose it is, and a corpse is a parent
--- like any other. Used to keep a body from being handed the opened food
--- as a destination.
function Open.onCorpse(item)
    if not item then return false end
    local container = item:getContainer()
    if not container then return false end

    local ok, parent = pcall(function() return container:getParent() end)
    if not ok or not parent then return false end
    return instanceof(parent, "IsoDeadBody") == true
end

--- Builds the same crafting logic the vanilla context menu would.
local function buildLogic(player, item, recipe)
    local logic = HandcraftLogic.new(player, nil, nil)
    logic:setIsoObject(logic:findCraftSurface(player, 2))
    logic:setContainers(containersOf(player))
    logic:setRecipeFromContextClick(recipe, item)
    return logic
end

--- Every sealed tin and jar within reach - the ones being carried
--- first, so a full inventory is used up before anything is fetched.
---
--- `fullType` narrows it to one kind, the way "Open All Beans" does.
--- nil means everything.
function Open.collect(player, fullType, family)
    local seen = {}
    local matches = function(item)
        -- Judge each item exactly once.
        --
        -- getAllEvalRecurse on the main inventory already walks every worn
        -- bag, and getContainers hands those same bags back as entries of
        -- its own, so the loop below offers their contents a second time.
        -- The only guard was `item:getContainer() ~= inventory`, which is
        -- true for a bag, so every tin in one was collected twice, counted
        -- twice in the menu and queued for two crafts - the second of them
        -- against an input the first had already destroyed. Same dedupe,
        -- same reason, as Dismantle.collect.
        if seen[item] then return false end
        seen[item] = true

        if fullType and item:getFullType() ~= fullType then return false end
        return matchesFamily(item, family)
    end

    local carried, stored = {}, {}
    local inventory = player:getInventory()

    local mine = inventory:getAllEvalRecurse(matches, ArrayList.new())
    if mine then
        for i = 0, mine:size() - 1 do
            table.insert(carried, mine:get(i))
        end
    end

    local containers = containersOf(player)
    for i = 0, containers:size() - 1 do
        local container = containers:get(i)
        if container and container ~= inventory then
            local found = container:getAllEvalRecurse(matches, ArrayList.new())
            if found then
                for j = 0, found:size() - 1 do
                    local item = found:get(j)
                    -- getContainers can hand back the same container
                    -- twice, and recursing into bags can reach an item
                    -- already counted.
                    if item:getContainer() ~= inventory then
                        table.insert(stored, item)
                    end
                end
            end
        end
    end

    for _, item in ipairs(stored) do
        table.insert(carried, item)
    end
    return carried
end

--- How many of them can actually be opened right now, and how many
--- there are. Runs inside a cache: this is the count the menu shows.
--- @return number doable, number total
local function countDoableNow(player, fullType, family)
    local items = Open.collect(player, fullType, family)
    if #items == 0 then return 0, 0 end

    local containers = containersOf(player)

    if family.batchSizes then
        local groups = {}
        for _, item in ipairs(items) do
            local itemType = item:getFullType()
            groups[itemType] = groups[itemType] or {}
            table.insert(groups[itemType], item)
        end

        local doable = 0
        for itemType, grouped in pairs(groups) do
            local required = family.batchSizes[itemType]
            if required and #grouped >= required then
                local recipe = recipeFor(player, grouped[1], containers, family)
                if recipe then
                    local logic = buildLogic(player, grouped[1], recipe)
                    if logic:canPerformCurrentRecipe() then
                        local possible = logic:getPossibleCraftCount(true) or 0
                        doable = doable + math.min(math.floor(#grouped / required), possible)
                    end
                end
            end
        end
        return doable, #items
    end

    local doable = 0
    for _, item in ipairs(items) do
        if recipeFor(player, item, containers, family) then doable = doable + 1 end
    end
    return doable, #items
end

function Open.countDoable(player, fullType, family)
    local doable, total = withCache(countDoableNow, player, fullType, family)
    return doable or 0, total or 0
end

---------------------------------------------------------------------
-- the job
---------------------------------------------------------------------

--- The borrowed inputs a craft would carry straight back - the can
--- opener, the knife.
local function borrowedSupplies(player, logic)
    local out = {}
    local data = logic:getRecipeData()
    if not data then return out end

    local putBack = data:getAllPutBackInputItems()
    if not putBack then return out end

    local inventory = player:getInventory()
    for i = 0, putBack:size() - 1 do
        local item = putBack:get(i)
        if item and item:getContainer() ~= inventory then
            table.insert(out, item)
        end
    end
    return out
end

--- Phase one: bring the tool and the tins into the inventory.
local function queueGathering(task)
    local player = task.player
    local moved = 0

    for _, item in ipairs(task.supplies) do
        ISInventoryPaneContextMenu.transferIfNeeded(player, item)
        moved = moved + 1
    end

    for _, item in ipairs(task.items) do
        if item:getContainer() ~= player:getInventory() then
            ISInventoryPaneContextMenu.transferIfNeeded(player, item)
            moved = moved + 1
        end
    end

    return moved
end

--- A snapshot of the main inventory, used to work out what the crafts
--- actually produced. Same approach as Auto Dismantle: the outputs of
--- three of these recipes come from an itemMapper and two more are
--- decided in Java, so an expected-type list would be wrong.
local function snapshotInventory(player)
    local seen = {}
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        seen[items:get(i)] = true
    end
    return seen
end

--- Phase two: with everything in hand, queue the crafts back to back.
local function queueCrafting(task)
    local player     = task.player
    local playerNum  = player:getPlayerNum()
    local containers = containersOf(player)
    local queued     = 0
    local unsettled  = 0
    local pending    = {}

    task.before = snapshotInventory(player)
    task.awaitingResults = true

    if task.family.batchSizes then
        local item = task.items[1]
        local container = item and item:getContainer()
        local recipe = container and recipeFor(player, item, containers, task.family) or nil

        if recipe then
            ISInventoryPaneContextMenu.OnNewCraft(item, recipe, playerNum, false, nil)
            task.pendingItems = { item }
            return 1, 0
        end

        if item and not container then unsettled = 1 end
        task.pendingItems = {}
        return 0, unsettled
    end

    for _, item in ipairs(task.items) do
        -- Re-checked per item: an item may have been eaten, dropped or
        -- opened by hand while the transfers ran.
        local container = item:getContainer()
        local recipe = container and recipeFor(player, item, containers, task.family) or nil

        if recipe then
            ISInventoryPaneContextMenu.OnNewCraft(item, recipe, playerNum, false, nil)
            queued = queued + 1
            table.insert(pending, item)
        elseif not container then
            -- Not gone: in transit.
            --
            -- ISInventoryTransferAction removes the item from the source
            -- before the destination takes it, and on a client the second
            -- half waits on the server. An item caught in that gap has no
            -- container for a moment, and the gathering phase hands over
            -- the instant its queue drains, which is exactly that moment.
            -- A client batch is one tin, so that one tin is the whole
            -- round: it queued nothing and the job stopped with "no can
            -- opener" on round one, every time. Auto Dismantle carries the
            -- same counter for the same reason. Waiting a tick is free.
            unsettled = unsettled + 1
        else
            -- Which of the two it was. The round diagnostic can already say
            -- the batch was planned and then queued nothing, but not
            -- whether the tin went missing or the engine stopped offering
            -- the recipe, and those have completely different causes.
            print("[AutoAll] open cannot craft " .. tostring(item:getFullType())
                    .. ": container=" .. tostring(container and "yes" or "GONE")
                    .. " recipe=" .. tostring(recipe and "yes" or "NONE")
                    .. " inInventory=" .. tostring(container == player:getInventory())
                    .. " containers=" .. tostring(containers and containers:size() or -1))
        end
    end

    task.pendingItems = pending
    return queued, unsettled
end

-- Rounds in a row where nothing was consumed before the job is called
-- stuck. Same figure the other two batch jobs use.
local MAX_NO_PROGRESS = 3

-- Rounds in a row that planned a batch and then queued no craft at all.
local MAX_EMPTY_CRAFTS = 3

-- Ticks a batch may wait for a transfer to land before it is treated as a
-- stale plan rather than a slow one. think() runs 250ms apart and the
-- server ack takes two or three seconds, so this covers 3.5s.
local MAX_UNSETTLED = 14

--- Did the crafts queued last round actually happen?
---
--- The queue draining is not evidence - ISHandcraftAction:isValid()
--- never checks that the inputs still exist. Every one of these recipes
--- consumes the sealed container, so an input that still has a
--- container was never opened.
local function confirmPendingCrafts(task)
    if #task.pendingItems == 0 then return true end

    local succeeded = 0
    for _, item in ipairs(task.pendingItems) do
        if not item:getContainer() then succeeded = succeeded + 1 end
    end

    AA.batchFeedback(task, #task.pendingItems, succeeded)

    task.pendingItems = {}
    task.succeeded = task.succeeded + succeeded

    if succeeded > 0 then
        task.noProgress = 0
        -- Real work landed, so the stall count starts over. Without this
        -- the counter is cumulative and three recoveries spread across a
        -- whole job end it, even though each one worked and the job kept
        -- going.
        task.stalls = 0
        return true
    end

    task.noProgress = task.noProgress + 1
    return task.noProgress < MAX_NO_PROGRESS
end

--- Puts the can opener back where it came from, once, at the end.
local function returnSupplies(task)
    if not AA.opt("openReturnItems") then return end

    local player = task.player
    for _, entry in ipairs(task.borrowedFrom) do
        if entry.item and entry.item:getContainer() == player:getInventory() then
            ISCraftingUI.ReturnItemToOriginalContainer(player, entry.item)
        end
    end
end

--- Notes what the last round of crafts actually produced.
---
--- Run once per round and accumulated, because task.before is replaced
--- every time crafts are queued: diffing only at the end would see just
--- the final round and leave every earlier tin in the character's bag.
local function collectResults(task)
    if not task.awaitingResults then return end
    task.awaitingResults = false

    local after = snapshotInventory(task.player)
    for item in pairs(after) do
        if not task.before[item] then task.results[item] = true end
    end
    task.before = {}
end

--- Sends the opened food back to the container the sealed one came
--- from, so emptying a fridge of tins does not end with the character
--- carrying every one of them.
local function returnResults(task)
    if not AA.opt("openResultsToSource") then return end

    local player      = task.player
    local destination = task.destination
    local inventory   = player:getInventory()
    if not destination or destination == inventory then return end

    for item in pairs(task.results) do
        -- Still there, and still ours to move: the character may have
        -- eaten one while the job ran.
        if item:getContainer() == inventory then
            ISTimedActionQueue.add(
                ISInventoryTransferAction:new(player, item, inventory, destination))
        end
    end
end

-- Safety net on the round loop. Each round does at least one tin.
local MAX_ROUNDS = 40
local MAX_ROUNDS_CLIENT = 300
local MAX_PACKING_ROUNDS = 300

local function roundBudget(task)
    if task and task.roundLimit then return task.roundLimit end
    return isClient() and MAX_ROUNDS_CLIENT or MAX_ROUNDS
end

local function packingRound(task, items, containers)
    local groups = {}
    local order = {}

    for _, item in ipairs(items) do
        local itemType = item:getFullType()
        if not groups[itemType] then
            groups[itemType] = {}
            order[#order + 1] = itemType
        end
        table.insert(groups[itemType], item)
    end

    local configMax = AA.opt("openMax") or 0
    if configMax > 0 and task.succeeded >= configMax then
        task.failReason = "nothing"
        return false
    end

    for _, itemType in ipairs(order) do
        local grouped = groups[itemType]
        local required = task.family.batchSizes[itemType]
        if required and #grouped >= required then
            local first = grouped[1]
            local recipe = recipeFor(task.player, first, containers, task.family)
            if recipe then
                local logic = buildLogic(task.player, first, recipe)
                local possible = logic:getPossibleCraftCount(true) or 0
                task.lastOpenable = math.floor(#grouped / required)
                task.lastPossible = possible
                task.lastDoable = math.min(task.lastOpenable, possible)

                if possible > 0 and logic:canPerformCurrentRecipe() then
                    local batch = {}
                    for i = 1, required do batch[i] = grouped[i] end

                    task.failReason = nil
                    task.items = batch
                    task.supplies = {}
                    task.phase = "gathering"

                    if queueGathering(task) == 0 then
                        task.phase = "crafting"
                        local queued = queueCrafting(task)
                        task.queued = task.queued + queued
                        if queued == 0 then
                            task.failReason = "blocked"
                        else
                            task.emptyCrafts = 0
                        end
                        return queued > 0
                    end

                    return true
                end
            end
        end
    end

    task.failReason = "blocked"
    return false
end

--- Works out what can be opened right now and queues the fetching for
--- it. Returns false when there is nothing left to do.
local function planRound(task)
    local player = task.player

    local items = Open.collect(player, task.fullType, task.family)
    task.lastItems = #items
    task.lastOpenable, task.lastDoable, task.lastPossible = nil, nil, nil
    if #items == 0 then
        task.failReason = "nothing"
        return false
    end

    local containers = containersOf(player)

    if task.family.batchSizes then
        return packingRound(task, items, containers)
    end

    -- Only the ones the game will actually give a recipe for, and the
    -- logic is built from the first of those rather than from the first
    -- item found - a jar and a tin do not share a recipe.
    local openable, first, recipe = {}, nil, nil
    for _, item in ipairs(items) do
        local r = recipeFor(player, item, containers, task.family)
        if r then
            if not first then first, recipe = item, r end
            table.insert(openable, item)
        end
    end
    task.lastOpenable = #openable
    if not first then
        -- Nothing in the pile has a recipe at all: that is the pile, not
        -- the tool. Told apart the way Auto Dismantle tells them apart.
        task.failReason = "blocked"
        return false
    end

    local logic = buildLogic(player, first, recipe)
    if not logic:canPerformCurrentRecipe() then
        -- Something had a recipe but the logic would not run it: that is
        -- the tool.
        task.failReason = "notool"
        return false
    end

    -- Capped by what the game says it can actually do, the way Auto
    -- Sterilize and Auto Dismantle both cap theirs. Without this the whole
    -- openable pile was queued in one go, so a batch bigger than the
    -- opener, the knife or the pile itself could cover ran crafts against
    -- inputs that were already gone. The argument is "recalculate", not a
    -- filter: with false the engine skips the maths and hands back a
    -- cached zero.
    local possible = logic:getPossibleCraftCount(true) or 0
    if possible < 0 then possible = 0 end
    task.lastPossible = possible

    local doable = math.min(possible, #openable)

    local configMax = AA.opt("openMax") or 0
    if configMax > 0 then
        -- Measured against what has been queued, not against what has been
        -- confirmed. The confirmation lands a round late, so counting
        -- succeeded let round after round plan a full cap's worth before
        -- the first of them had been scored, and the job overshot.
        doable = math.min(doable, math.max(0, configMax - task.queued))
    end

    -- On a client the batch is only as big as the last round earned.
    -- See AA.batchSize in the core.
    local clientCap = AA.batchSize(task)
    if clientCap then doable = math.min(doable, clientCap) end

    task.lastDoable = doable

    if doable <= 0 then
        task.failReason = "blocked"
        return false
    end

    task.failReason = nil

    local batch = {}
    for i = 1, doable do
        batch[i] = openable[i]
    end

    local supplies = borrowedSupplies(player, logic)
    for _, item in ipairs(supplies) do
        if not task.borrowedSeen[item] then
            task.borrowedSeen[item] = true
            task.borrowedFrom[#task.borrowedFrom + 1] =
                { item = item, container = item:getContainer() }
        end
    end

    task.items    = batch
    task.supplies = supplies
    task.phase    = "gathering"

    if queueGathering(task) == 0 then
        -- Nothing had to be fetched, so there is nothing to wait for.
        task.phase = "crafting"
        local queued = queueCrafting(task)
        task.queued = task.queued + queued
        if queued == 0 then
            task.failReason = "blocked"
        else
            task.emptyCrafts = 0
        end
        return queued > 0
    end

    return true
end

-- Why the last round could not be planned.
--
-- Every dead end used to say "No can opener or sharp knife within reach",
-- including the ones with an opener in hand - an empty pile, a stale batch
-- and a tin the engine will not offer a recipe for all ended there. Same
-- three-way split, and the same diagnostic line, as Auto Dismantle.
--
-- The three reasons are named the same way in every family's text table,
-- so the split survives a job that is opening ammo boxes rather than tins.
-- A carton needs no tool, and that family points notool at the same
-- string as blocked rather than pretending a can opener is missing.

local function stopText(task)
    -- One line naming the dead end, because "none of them can be opened
    -- right now" is the honest message and still not a diagnosis.
    -- Everything the planner decided from, in the order it decided it.
    print("[AutoAll] open stopping: family=" .. tostring(task.family and task.family.key)
            .. " reason=" .. tostring(task.failReason or "unset")
            .. " items=" .. tostring(task.lastItems)
            .. " openable=" .. tostring(task.lastOpenable)
            .. " doable=" .. tostring(task.lastDoable)
            .. " possible=" .. tostring(task.lastPossible)
            .. " batch=" .. tostring(task.batchSize)
            .. " queued=" .. tostring(task.queued)
            .. " succeeded=" .. tostring(task.succeeded)
            .. " rounds=" .. tostring(task.rounds)
            .. " emptyCrafts=" .. tostring(task.emptyCrafts or 0))
    local text = task.family.text
    return getText(text[task.failReason] or text.blocked)
end

--- One round, inside a cache. Every recipe lookup a round makes asks
--- the same question of the same item types, so one cache per round is
--- the difference between a lookup per tin and a lookup per type.
local function beginRound(task)
    return withCache(planRound, task) == true
end

local function think(task)
    local player = task.player

    if AA.isQueueBusy(player) then return end

    collectResults(task)

    if not confirmPendingCrafts(task) then
        AA.stop(player, getText("UI_AA_stop_error"), true)
        return
    end

    if task.phase == "gathering" then
        task.phase = "crafting"
        AA.reason(task, getText(task.family.text.working))
        local queued, unsettled = withCache(queueCrafting, task)
        queued = queued or 0
        unsettled = unsettled or 0
        task.queued = task.queued + queued

        if queued == 0 then
            -- Nothing was crafted, so there is nothing for collectResults
            -- to diff against: a tin that lands from here is a transfer
            -- arriving, not something a craft produced, and counting it as
            -- a result would post a still-sealed tin to the destination.
            -- queueCrafting takes a fresh snapshot the next time it runs.
            task.awaitingResults = false
        end

        -- Nothing queued, but only because a transfer had not landed yet.
        -- Come back next tick with the same batch instead of spending a
        -- re-plan on it. Bounded, so a tin that really has gone still falls
        -- through to the re-plan below.
        if queued == 0 and unsettled > 0
                and (task.unsettled or 0) < MAX_UNSETTLED then
            task.unsettled = (task.unsettled or 0) + 1
            task.phase = "gathering"
            return
        end
        task.unsettled = 0

        if queued == 0 then
            -- The plan was made before the fetching ran, and fetching moves
            -- the character. Walking to a fridge changes which containers
            -- the loot window holds, and containersOf reads that window, so
            -- a recipe that resolved while standing in front of it can stop
            -- resolving once the character has stepped away. On a client a
            -- transfer can also be discarded in silence.
            --
            -- Either way the batch is stale, not impossible. Re-plan
            -- against the world as it is now rather than declaring the
            -- whole pile untouchable. Bounded, so a pile that genuinely
            -- cannot be worked still ends rather than spinning.
            task.emptyCrafts = (task.emptyCrafts or 0) + 1
            if task.emptyCrafts < MAX_EMPTY_CRAFTS and task.rounds < roundBudget(task) then
                print("[AutoAll] open re-planning after an empty craft round ("
                        .. tostring(task.emptyCrafts) .. "/"
                        .. tostring(MAX_EMPTY_CRAFTS) .. ")")
                task.rounds = task.rounds + 1
                if beginRound(task) then return end
            end

            task.failReason = task.failReason or "blocked"
            AA.stop(player, stopText(task), true)
        else
            task.emptyCrafts = 0
        end
        return
    end

    if task.phase == "returning" then
        task.phase = "results"
        returnResults(task)
        return
    end

    if task.phase == "results" then
        AA.stop(player, getText(task.family.text.done, task.succeeded), false)
        return
    end

    if task.rounds < roundBudget(task) then
        task.rounds = task.rounds + 1
        if beginRound(task) then return end
    end

    -- The tool goes home first, then the food, then the job ends. Each
    -- of those is its own pass through think() because AA.stop clears
    -- the action queue: queueing a transfer and stopping in the same
    -- tick wipes the transfer.
    task.phase = "returning"
    returnSupplies(task)
end

function Open.start(player, fullType, label, destination, familyKey)
    if not player then return end

    local family = FAMILIES[familyKey or "food"]
    if not family then return end

    local items = withCache(Open.collect, player, fullType, family) or {}

    if #items == 0 then
        HaloTextHelper.addBadText(player, getText(family.text.nothing))
        return
    end

    -- Where the opened food goes at the end. Falls back to the container
    -- the first of the batch came from when the option was used on
    -- something already carried.
    --
    -- A corpse is never a destination, however the option is set: pushing
    -- opened tins into the body they came off is not "back where they came
    -- from", it is losing them. The clicked destination is guarded in the
    -- menu, this is the same guard on the fallback.
    local fallback = items[1] and items[1]:getContainer() or nil
    if fallback and Open.onCorpse(items[1]) then fallback = nil end

    local startCount = #items
    if family.batchSizes then
        local grouped = {}
        startCount = 0
        for _, item in ipairs(items) do
            local itemType = item:getFullType()
            grouped[itemType] = (grouped[itemType] or 0) + 1
        end
        for itemType, count in pairs(grouped) do
            startCount = startCount + math.floor(count / family.batchSizes[itemType])
        end
    end

    local task = {
        kind         = "open",
        player       = player,
        -- One job kind for all three families, because only one task runs
        -- at a time anyway. The family is what the messages and the
        -- matching read.
        family       = family,
        fullType     = fullType,        -- nil means "everything in reach"
        items        = {},
        supplies     = {},
        borrowedFrom = {},
        borrowedSeen = {},
        destination  = destination or fallback,
        before       = {},
        results      = {},
        queued       = 0,
        succeeded    = 0,
        pendingItems = {},
        noProgress   = 0,
        rounds       = 0,
        roundLimit   = family.batchSizes and math.max(MAX_PACKING_ROUNDS,
            startCount + MAX_NO_PROGRESS + MAX_EMPTY_CRAFTS) or nil,
        emptyCrafts  = 0,
        unsettled    = 0,
        failReason   = nil,
        -- A single action that never ends freezes the whole job in
        -- silence: think() is gated on the queue draining, so nothing
        -- is ever said and nothing is written to the log.
        stallTimeout = 30000,
        phase        = "gathering",
        think        = think,
        allowMove    = true,
        startText    = getText(family.text.started, startCount, label),
    }

    AA.startTask(task)

    if not beginRound(task) then
        AA.stop(player, stopText(task), true)
    end
end

Open.onStartAll = function(player, args)
    local family = FAMILIES[args and args.family or "food"] or FAMILIES.food
    Open.start(player, nil, getText(family.text.labelAll), nil, family.key)
end

Open.onStartOne = function(player, args)
    Open.start(player, args.fullType, args.label, args.destination, args.family)
end

Open.onStop = function(player)
    AA.stop(player, getText("UI_AA_stopped"), false)
end

---------------------------------------------------------------------
-- context menu
---------------------------------------------------------------------

local function addEntry(context, player, family, label, fullType, callback, args)
    local doable, total = Open.countDoable(player, fullType, family)
    if total == 0 then return end

    local option = AA.addOption(context, label, player, callback, args)
    local tooltip = ISInventoryPaneContextMenu.addToolTip()

    if doable == 0 then
        -- Greyed with the reason rather than hidden, so it is clear the
        -- option exists and only the can opener is missing.
        option.notAvailable = true
        tooltip.description = getText(family.text.notool)
    else
        tooltip.description = getText(family.text.optionTt, doable, total)
    end
    option.toolTip = tooltip
end

local function addOpenMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end

    local actual = ISInventoryPane.getActualItems(items)
    local item = actual and actual[1]
    if not item or not instanceof(item, "InventoryItem") then return end

    -- The whole menu hangs off the clicked item being a sealed
    -- container. Nothing below this line runs on a right click
    -- anywhere else, which is what keeps the cost off every menu.
    local family = Open.familyOf(item)
    local packingFamily = Open.packingFamilyOf(item)
    if not family and not packingFamily then return end

    if AA.isRunning(player, "open") then
        -- Named after the job that is running, not after the thing that
        -- happens to be under the cursor.
        local running = AA.getTask(player)
        local stop = running and running.family and running.family.text.stop
        AA.addOption(context, getText(stop or "UI_AA_open_stop"), player, Open.onStop)
        return
    end

    -- One cache around both entries. Each of them counts what is within
    -- reach, and both ask the crafting engine about the same item types.
    -- Right clicking one inside a fridge, a crate or on the floor sends the
    -- opened food back there. Used on something already carried, it stays
    -- in the inventory.
    -- A corpse is never a destination, however the option is set: pushing
    -- opened tins into the body they came off is not "back where they came
    -- from", it is losing them.
    local clicked = item:getContainer()
    local destination = nil
    if clicked and clicked ~= player:getInventory() and not Open.onCorpse(item) then
        destination = clicked
    end

    withCache(function()
        if family then
            local fullType = item:getFullType()
            addEntry(context, player, family,
                getText(family.text.option, item:getDisplayName()),
                fullType, Open.onStartOne,
                { fullType = fullType, label = item:getDisplayName(),
                  destination = destination, family = family.key })

            addEntry(context, player, family, getText(family.text.optionAll),
                nil, Open.onStartAll, { family = family.key })
        end

        if packingFamily then
            addEntry(context, player, packingFamily,
                getText(packingFamily.text.optionAll), nil, Open.onStartAll,
                { family = packingFamily.key })
        end
    end)
end

AA.registerMenu("open", Events.OnFillInventoryObjectContextMenu, addOpenMenu)
