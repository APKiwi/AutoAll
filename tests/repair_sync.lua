local failures = 0
local root = arg[0]:match("^(.*)/tests/repair_sync%.lua$") or "."
local hookPath = root
        .. "/Contents/mods/AutoAll/42/media/lua/server/AutoAll/AutoAll_RepairSync.lua"

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

local function assertSame(actual, expected, message)
    if not rawequal(actual, expected) then
        fail(message or "expected the same value")
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

local function fixture(options)
    options = options or {}
    local callbacks = {}
    local calls = {}
    local required = {}
    local originalCalls = 0
    local equipped

    local clothing = {
        hole = options.hole == nil and 1 or options.hole,
        condition = 60,
        patch = options.patch,
    }
    local client = { hole = clothing.hole, condition = clothing.condition, patch = clothing.patch }
    local observer = { hole = clothing.hole, condition = clothing.condition }
    local character = { player = options.player ~= false }

    function clothing:getVisual() return self end
    function clothing:getHole() return self.hole end
    function clothing:getPatchType() return self.patch end
    function character:isEquippedClothing(item) return equipped == item end

    if options.equipped ~= false then equipped = clothing end

    local action = {
        character = character,
        clothing = clothing,
        fabric = {},
        thread = {},
        needle = {},
        part = "Torso_Upper",
    }
    if options.nilParams then
        action.clothing = nil
        action.fabric = nil
        action.thread = nil
        action.needle = nil
    end

    local function defaultComplete(self)
        originalCalls = originalCalls + 1
        calls[#calls + 1] = "original"
        if options.result == false then return false end
        if options.ordinaryPatch then
            self.clothing.hole = 0
            self.clothing.patch = "Cotton"
        elseif not options.unchanged and self.clothing then
            self.clothing.hole = 0
            self.clothing.condition = 70
            self.clothing.patch = nil
        end
        if options.unequip then equipped = nil end
        if options.replaceActionClothing then self.clothing = options.replaceActionClothing end
        return options.result == nil and true or options.result
    end

    local env = setmetatable({
        ISRepairClothing = { complete = options.complete or defaultComplete },
        Events = {
            OnServerStarted = {
                Add = function(callback) callbacks[#callbacks + 1] = callback end,
            },
        },
        isServer = function() return options.server ~= false end,
        isClient = function() return options.client == true end,
        instanceof = function(value, className)
            return value == character and value.player and className == "IsoPlayer"
        end,
        require = function(name) required[#required + 1] = name end,
        syncVisuals = function(value)
            assertSame(value, character, "visual sync player")
            calls[#calls + 1] = "visuals"
            client.hole = clothing.hole
            client.condition = clothing.condition
            observer.hole = clothing.hole
            observer.condition = clothing.condition
        end,
        syncClothingFields = function(value)
            assertSame(value, character, "field sync player")
            calls[#calls + 1] = "fields"
            client.hole = clothing.hole
            client.condition = clothing.condition
            client.patch = clothing.patch
        end,
        print = function() end,
    }, { __index = _G })

    local chunk, message = loadfile(hookPath, "t", env)
    if not chunk then fail(message) end
    chunk()

    return {
        action = action,
        callbacks = callbacks,
        calls = calls,
        character = character,
        client = client,
        clothing = clothing,
        observer = observer,
        required = required,
        env = env,
        fire = function()
            for _, callback in ipairs(callbacks) do callback() end
        end,
        complete = function(self, ...)
            return env.ISRepairClothing.complete(self or action, ...)
        end,
        originalCalls = function() return originalCalls end,
        setComplete = function(value) env.ISRepairClothing.complete = value end,
    }
end

run("a full repair refreshes the owner item and observer visuals after completion", function()
    local game = fixture()
    game.fire()

    local clientItem = game.client
    assertEqual(game.complete(), true, "completion return")
    assertSame(game.client, clientItem, "client item identity")
    assertEqual(game.client.hole, 0, "owner hole")
    assertEqual(game.client.condition, 70, "owner condition")
    assertEqual(game.client.patch, nil, "owner patch")
    assertEqual(game.observer.hole, 0, "observer hole")
    assertEqual(game.observer.condition, 70, "observer condition")
    assertEqual(table.concat(game.calls, ","), "original,visuals,fields", "send order")
    assertEqual(game.originalCalls(), 1, "original call count")
end)

run("a failed repair passes through without synchronization", function()
    local game = fixture({ result = false })
    game.fire()

    assertEqual(game.complete(), false, "completion return")
    assertEqual(table.concat(game.calls, ","), "original", "calls")
    assertEqual(game.originalCalls(), 1, "original call count")
end)

run("nil repair parameters pass through without synchronization", function()
    local game = fixture({ nilParams = true, result = false })
    game.fire()

    assertEqual(game.complete(), false, "completion return")
    assertEqual(table.concat(game.calls, ","), "original", "calls")
    assertEqual(game.originalCalls(), 1, "original call count")
end)

run("an ordinary patch keeps the vanilla packet baseline", function()
    local game = fixture({ ordinaryPatch = true })
    game.fire()

    assertEqual(game.complete(), true, "completion return")
    assertEqual(game.clothing.patch, "Cotton", "patch type")
    assertEqual(table.concat(game.calls, ","), "original", "calls")
end)

run("unchanged successful actions do not synchronize", function()
    local game = fixture({ unchanged = true })
    game.fire()

    assertEqual(game.complete(), true, "completion return")
    assertEqual(game.clothing.hole, 1, "remaining hole")
    assertEqual(table.concat(game.calls, ","), "original", "calls")
end)

run("carried clothing does not get extra packets", function()
    local game = fixture({ equipped = false })
    game.fire()

    assertEqual(game.complete(), true, "completion return")
    assertEqual(table.concat(game.calls, ","), "original", "calls")
end)

run("clothing without a preexisting hole does not get extra packets", function()
    local game = fixture({ hole = 0 })
    game.fire()

    assertEqual(game.complete(), true, "completion return")
    assertEqual(table.concat(game.calls, ","), "original", "calls")
end)

run("a garment removed during completion does not synchronize", function()
    local game = fixture({ unequip = true })
    game.fire()

    assertEqual(game.complete(), true, "completion return")
    assertEqual(table.concat(game.calls, ","), "original", "calls")
end)

run("a nonplayer repair passes through without calling player sync APIs", function()
    local game = fixture({ player = false })
    game.fire()

    assertEqual(game.complete(), true, "completion return")
    assertEqual(table.concat(game.calls, ","), "original", "calls")
end)

run("singleplayer and client loads leave the completion function untouched", function()
    for _, mode in ipairs({
        { server = false, client = false, label = "singleplayer" },
        { server = false, client = true, label = "client" },
    }) do
        local game = fixture(mode)
        local original = game.env.ISRepairClothing.complete

        assertEqual(#game.callbacks, 0, mode.label .. " callback count")
        assertEqual(#game.required, 0, mode.label .. " require count")
        assertSame(game.env.ISRepairClothing.complete, original, mode.label .. " complete function")
    end
end)

run("repeated server start events do not stack wrappers", function()
    local game = fixture()
    game.fire()
    game.fire()

    assertEqual(game.complete(), true, "completion return")
    assertEqual(game.originalCalls(), 1, "original call count")
    assertEqual(table.concat(game.calls, ","), "original,visuals,fields", "calls")
end)

run("a completion replacement made before server start stays in the chain", function()
    local game = fixture()
    local marker = {}
    local customCalls = 0
    game.setComplete(function(self, argument)
        customCalls = customCalls + 1
        assertSame(argument, marker, "custom argument")
        self.clothing.hole = 0
        self.clothing.condition = 75
        return true, "custom return"
    end)
    game.fire()

    local result, detail = game.complete(nil, marker)
    assertEqual(result, true, "completion return")
    assertEqual(detail, "custom return", "second return")
    assertEqual(customCalls, 1, "custom call count")
    assertEqual(game.client.condition, 75, "custom mutation synchronized")
    assertEqual(table.concat(game.calls, ","), "visuals,fields", "calls")
end)

run("an original completion exception propagates without synchronization", function()
    local token = {}
    local game = fixture({ complete = function() error(token) end })
    game.fire()

    local ok, message = pcall(game.complete)
    assertEqual(ok, false, "completion status")
    assertSame(message, token, "completion error")
    assertEqual(#game.calls, 0, "sync call count")
end)

if failures > 0 then
    error(tostring(failures) .. " repair sync test(s) failed")
end
