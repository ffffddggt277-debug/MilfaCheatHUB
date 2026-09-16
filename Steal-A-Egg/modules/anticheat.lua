-- MilfaCheatHUB • anticheat bypass core v0.5.0
-- Counter-measures against the game's client anticheat (kick codes BAC-4513 / BAC-75110).
-- Techniques borrowed from public working scripts (Phemonaz "Anti Cheat Bypass",
-- rscripts "Steal an Egg WalkSpeed + anticheat bypass", Exunys "Anti-Kick"):
--   1) Freeze anticheat state tables found via getgc -> blocks incident writes (kick reports)
--   2) Blind the movement sampler: the AC module hides behind the source name
--      "ContentCatalog.Runtime"; its sampler (3 params, 5 upvalues) returns
--      {WalkSpeed, Position, Timestamp} — we falsify WalkSpeed in the sample
--   3) Mask executor HttpGet/HttpPost probes coming from game scripts (look vanilla)
--   4) Block client-side LocalPlayer:Kick as the last line of defense
--   5) Optional WalkSpeed write-lock via __newindex (blocks AC speed resets)
-- Server-side kicks never pass through Lua and cannot be blocked from the client.

local AC = {}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

AC.Status = {
    NamecallHooked = false,
    NewindexHooked = false,
    StatesFrozen = 0,
    SamplersBlinded = 0,
    BlockedKicks = 0,
    BlockedProbes = 0,
}

local StealthRef = nil
local SettingsRef = nil

local function hasExecutorCore()
    return type(hookmetamethod) == "function"
        and type(newcclosure) == "function"
        and type(getnamecallmethod) == "function"
end

local function hasGarbageCore()
    return type(getgc) == "function"
        and type(islclosure) == "function"
        and type(debug) == "table"
        and type(debug.info) == "function"
        and type(debug.getupvalues) == "function"
end

---------------------------------------------------------------------
-- 1) Freeze anticheat state tables (Phemonaz method).
-- Self-referencing tables without a metatable that also have a numeric
-- "hole" at index 1..3 get a blocking __newindex metatable, so the AC
-- can no longer append incident entries that would later be reported.
---------------------------------------------------------------------
local MAX_TABLE_SCAN = 2048

function AC.FreezeStates()
    if type(getgc) ~= "function" or type(setmetatable) ~= "function" then
        return 0
    end

    local frozen = 0
    pcall(function()
        local okGC, garbage = pcall(getgc, true)
        if not okGC or type(garbage) ~= "table" then return end

        for _, obj in pairs(garbage) do
            if typeof(obj) == "table" and not getrawmetatable(obj) then
                -- Cheap size guard: anticheat state tables are small.
                local size = 0
                local selfRef = false
                for key, value in pairs(obj) do
                    size = size + 1
                    if value == obj then selfRef = true end
                    if size > MAX_TABLE_SCAN then break end
                end
                if selfRef and size <= MAX_TABLE_SCAN then
                    for key, value in pairs(obj) do
                        if typeof(key) == "number" and key >= 1 and key <= 3 and obj[key] == nil then
                            pcall(setmetatable, obj, {__newindex = function() end})
                            frozen = frozen + 1
                            break
                        end
                    end
                end
            end
        end
    end)

    AC.Status.StatesFrozen = frozen
    return frozen
end

---------------------------------------------------------------------
-- 2) Blind the movement sampler (rscripts method).
---------------------------------------------------------------------
function AC.BlindSamplers()
    if not hasGarbageCore() or type(hookfunction) ~= "function" then
        return 0
    end

    local targets = {}
    pcall(function()
        local okGC, garbage = pcall(getgc)
        if not okGC or type(garbage) ~= "table" then return end

        for _, fn in pairs(garbage) do
            if typeof(fn) == "function" and islclosure(fn) then
                local okSrc, src = pcall(debug.info, fn, "s")
                if okSrc and type(src) == "string" and src:find("ContentCatalog%.Runtime") then
                    local okArgs, argCount = pcall(debug.info, fn, "a")
                    local okUps, upvalues = pcall(debug.getupvalues, fn)
                    if okArgs and argCount == 3 and okUps and type(upvalues) == "table" and #upvalues == 5 then
                        targets[#targets + 1] = fn
                    end
                end
            end
        end

        -- Fallback: same shape, looser source match (AC update renamed the disguise).
        if #targets == 0 then
            for _, fn in pairs(garbage) do
                if typeof(fn) == "function" and islclosure(fn) then
                    local okSrc, src = pcall(debug.info, fn, "s")
                    if okSrc and type(src) == "string" and src:find("Runtime") then
                        local okArgs, argCount = pcall(debug.info, fn, "a")
                        local okUps, upvalues = pcall(debug.getupvalues, fn)
                        if okArgs and argCount == 3 and okUps and type(upvalues) == "table" and #upvalues == 5 then
                            targets[#targets + 1] = fn
                        end
                    end
                end
            end
        end
    end)

    local blinded = 0
    for _, fn in ipairs(targets) do
        local ok = pcall(function()
            local original
            local wrapper
            wrapper = function(a, b, c)
                local sample = original(a, b, c)
                if type(sample) == "table" and sample.WalkSpeed and sample.Position and sample.Timestamp then
                    sample.WalkSpeed = 100000
                end
                return sample
            end
            if type(newlclosure) == "function" then
                pcall(function() wrapper = newlclosure(wrapper) end)
            end
            original = hookfunction(fn, wrapper)
            return original ~= nil
        end)
        if ok then blinded = blinded + 1 end
    end

    AC.Status.SamplersBlinded = blinded
    return blinded
end

---------------------------------------------------------------------
-- 3+4) Namecall guard: Kick block + HttpGet probe masking (Exunys-style).
-- Vanilla clients cannot call game:HttpGet from a LocalScript (plugin
-- security). If a game-script probe succeeds, the environment is flagged
-- as an executor. We answer probes with the vanilla security error.
-- Our own loader calls HttpGet via dot-syntax, which never hits __namecall.
---------------------------------------------------------------------
local PROBE_METHODS = {
    HttpGet = true,
    HttpPost = true,
    GetAsync = true,
    PostAsync = true,
    RequestAsync = true,
}

function AC.InstallNamecallGuard()
    if AC._namecallInstalled then return AC.Status.NamecallHooked end
    if not hasExecutorCore() then return false end
    AC._namecallInstalled = true

    local ok = pcall(function()
        local player = Players.LocalPlayer
        local original
        original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()

            -- Last line of defense: client-side kick.
            if method == "Kick" and self == player and StealthRef.BlockKick ~= false then
                AC.Status.BlockedKicks = AC.Status.BlockedKicks + 1
                warn("[MilfaCheatHUB] Заблокирован клиентский Kick (#" .. AC.Status.BlockedKicks .. ")")
                return nil
            end

            -- Look vanilla: deny executor-only methods to game scripts.
            if PROBE_METHODS[method] and SettingsRef.MaskHttpProbes ~= false and (self == game or self == HttpService) then
                local ours = false
                if type(checkcaller) == "function" then
                    ours = checkcaller()
                end
                if not ours then
                    AC.Status.BlockedProbes = AC.Status.BlockedProbes + 1
                    error("The current identity (2) cannot " .. method .. " (lacking plugin security access)", 2)
                end
            end

            return original(self, ...)
        end))
        AC.Status.NamecallHooked = original ~= nil
    end)

    return AC.Status.NamecallHooked
end

---------------------------------------------------------------------
-- 5) WalkSpeed write-lock (rscripts method), lazy __newindex hook.
-- Blocks every WalkSpeed write that does not match our target, so the
-- classic speed mode survives AC resets.
---------------------------------------------------------------------
function AC.EnableSpeedLock(target)
    AC.LockedWalkSpeed = (type(target) == "number" and target > 16) and target or nil

    if not AC.LockedWalkSpeed or AC._speedLockInstalled then return end
    if not hasExecutorCore() then return end
    AC._speedLockInstalled = true

    pcall(function()
        local player = Players.LocalPlayer
        local original
        original = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
            if AC.LockedWalkSpeed and key == "WalkSpeed" and type(value) == "number" then
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                if humanoid and self == humanoid and value ~= AC.LockedWalkSpeed then
                    return
                end
            end
            return original(self, key, value)
        end))
        AC.Status.NewindexHooked = original ~= nil
    end)
end

---------------------------------------------------------------------
-- Init + periodic rescan (AC tables appear lazily as game scripts run).
---------------------------------------------------------------------
function AC.Init(stealth, settings)
    StealthRef = stealth or StealthRef
    SettingsRef = settings or SettingsRef
    AC.Supported = hasExecutorCore()

    AC.InstallNamecallGuard()
    if SettingsRef.FreezeACStates ~= false then
        task.spawn(function() AC.FreezeStates() end)
    end
    if SettingsRef.BlindSamplers ~= false then
        task.spawn(function() AC.BlindSamplers() end)
    end

    -- Rescan passes: 5s / 15s / 30s after load.
    task.spawn(function()
        for _, delay in ipairs({5, 15, 30}) do
            task.wait(delay)
            if not StealthRef or StealthRef.Aborted then break end
            if SettingsRef.FreezeACStates ~= false then AC.FreezeStates() end
            if SettingsRef.BlindSamplers ~= false and AC.Status.SamplersBlinded == 0 then
                AC.BlindSamplers()
            end
        end
    end)

    return AC.Supported
end

function AC.Summary()
    local s = AC.Status
    return string.format(
        "заморожено %d • сэмплеров %d • кик-гард %s • пробы %s • хук NEWINDEX %s",
        s.StatesFrozen or 0,
        s.SamplersBlinded or 0,
        (StealthRef.BlockKick ~= false) and "ON" or "OFF",
        s.NamecallHooked and "маскированы" or "нет",
        s.NewindexHooked and "ON" or "OFF"
    )
end

return AC
