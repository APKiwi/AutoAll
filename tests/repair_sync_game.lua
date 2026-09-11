-- Runs the installed vanilla completion function. Java garment mutation and
-- network delivery are stubs, so this is not a live multiplayer test.
local root = arg[0]:match("^(.*)/tests/repair_sync_game%.lua$") or "."
local java = os.getenv("PZ_JAVA_DIR")
        or ((os.getenv("HOME") or "") .. "/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java")
local vanillaPath = java .. "/media/lua/shared/TimedActions/ISRepairClothing.lua"
local probe = io.open(vanillaPath, "r")
if not probe then
    if os.getenv("PZ_JAVA_DIR") then error("Cannot read " .. vanillaPath) end
    print("skip - installed repair action test (set PZ_JAVA_DIR)")
    return
end
probe:close()

local function equal(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
end

local function fixture(withHook, matching, worn)
    local calls = {}
    local callbacks = {}
    local cloth = { hole = 1, condition = 60, patch = nil }
    local client = { hole = 1, condition = 60, patch = nil }
    local inspectItem = client
    local observer = { hole = 1, condition = 60 }
    local fabric = { present = true }
    local inventory = {}
    local thread = { uses = 3 }
    local actor = {}
    local xp = 0

    function actor:isEquippedClothing(item) return worn and item == cloth end
    function actor:getInventory() return inventory end
    function inventory:Remove(item)
        equal(item, fabric, "vanilla consumes its original fabric")
        item.present = false
        calls[#calls + 1] = "consume fabric"
    end
    function thread:UseAndSync()
        self.uses = self.uses - 1
        calls[#calls + 1] = "consume thread"
    end
    function cloth:getVisual() return self end
    function cloth:getHole() return self.hole end
    function cloth:getPatchType() return self.patch end
    function cloth:getCondition() return self.condition end
    function cloth:canFullyRestore() return matching and self.hole > 0 end

    local function deliverVisuals()
        equal(fabric.present, false, "sync follows vanilla item consumption")
        equal(thread.uses, 2, "sync follows vanilla thread consumption")
        calls[#calls + 1] = "visuals"
        client.hole, client.condition = cloth.hole, cloth.condition
        observer.hole, observer.condition = cloth.hole, cloth.condition
    end
    local function deliverFields()
        calls[#calls + 1] = "fields"
        client.hole, client.condition, client.patch = cloth.hole, cloth.condition, cloth.patch
    end

    function cloth:addPatch(character, part, piece)
        equal(character, actor, "same repair actor")
        equal(piece, fabric, "same repair fabric")
        calls[#calls + 1] = "repair"
        if matching then
            -- Confirmed Clothing.addPatch bytecode: full repair returns
            -- before the equipped-clothing packet sends.
            self.hole = 0
            self.condition = 70
            return
        end
        self.hole = 0
        self.patch = "Cotton"
        -- Java sends these native packets directly, before Lua complete()
        -- consumes the supplies. They do not call the Lua sync helpers.
        calls[#calls + 1] = "native clothing"
        calls[#calls + 1] = "native visuals"
        client.hole, client.patch = self.hole, self.patch
        observer.hole = self.hole
    end

    local env = setmetatable({
        ISBaseTimedAction = { derive = function() return {} end },
        require = function() end,
        isServer = function() return true end,
        isClient = function() return false end,
        instanceof = function(value, name) return value == actor and name == "IsoPlayer" end,
        Perks = { Tailoring = "Tailoring" },
        sendRemoveItemFromContainer = function(inv, item)
            equal(inv, inventory, "same inventory")
            equal(item, fabric, "same consumed fabric")
        end,
        addXp = function(character, perk, amount)
            equal(character, actor, "same XP recipient")
            equal(perk, "Tailoring", "same XP skill")
            xp = xp + amount
        end,
        syncItemFields = function(character, item)
            equal(character, actor, "same field recipient")
            equal(item, cloth, "same field item")
            deliverFields()
        end,
        syncVisuals = function(character)
            equal(character, actor, "same visual recipient")
            deliverVisuals()
        end,
        syncClothingFields = function(character)
            equal(character, actor, "same clothing recipient")
            deliverFields()
        end,
        Events = { OnServerStarted = { Add = function(fn) callbacks[#callbacks + 1] = fn end } },
        print = function() end,
    }, { __index = _G })
    assert(loadfile(vanillaPath, "t", env))()
    if withHook then
        assert(loadfile(root .. "/Contents/mods/AutoAll/42/media/lua/server/AutoAll/AutoAll_RepairSync.lua", "t", env))()
        for _, callback in ipairs(callbacks) do callback() end
    end
    local action = setmetatable({
        character = actor, clothing = cloth, fabric = fabric,
        thread = thread, needle = {}, part = "Groin",
    }, { __index = env.ISRepairClothing })
    equal(action:complete(), true, "vanilla completion return value")
    equal(xp, 2, "vanilla XP unchanged")
    equal(thread.uses, 2, "one thread use")
    equal(fabric.present, false, "one fabric consumed")
    equal(inspectItem, client, "Inspect retains the same client item")
    return cloth, client, observer, calls
end

local server, client = fixture(false, true, true)
equal(server.hole, 0, "unpatched vanilla repaired the authoritative hole")
equal(client.hole, 1, "unpatched vanilla leaves the worn client hole stale")
print("ok - installed vanilla completion reproduces the missing worn update")

local observer, calls
server, client, observer, calls = fixture(true, true, true)
equal(client.hole, 0, "hook delivers restored hole to Inspect's item")
equal(client.condition, server.condition, "hook delivers restored condition")
equal(client.patch, nil, "full repair creates no patch")
equal(observer.hole, 0, "hook invokes visual delivery for observers")
equal(table.concat(calls, ","), "repair,consume fabric,consume thread,visuals,fields",
        "vanilla completion precedes one synchronization pair")
print("ok - installed vanilla completion with hook refreshes worn repair state")

server, client, observer, calls = fixture(true, true, false)
equal(client.hole, 0, "vanilla carried-item synchronization preserved")
equal(table.concat(calls, ","), "repair,consume fabric,consume thread,fields",
        "carried repair adds no extra packets")
print("ok - installed vanilla carried repair keeps its existing sync path")

server, client, observer, calls = fixture(true, false, true)
equal(client.patch, "Cotton", "ordinary patch remains a patch")
equal(table.concat(calls, ","), "repair,native clothing,native visuals,consume fabric,consume thread",
        "ordinary patch adds no workaround packets")
print("ok - installed vanilla patch keeps its existing sync path")
