-- MilfaCheatHUB • anticheat bypass core v0.6.0 (OPT-IN ONLY)
-- History lesson from the field:
--   v0.4.1 kick-guard (namecall hook)      -> kicked, CODE BAC-4513
--   v0.5.0 freeze + samplers + Http masking -> kicked, CODE BAC-2516
--   meanwhile open-source hubs with ZERO hooks run fine for hours.
-- Conclusion: this game's anticheat runs integrity/honeypot checks and flags
-- tampering. Every counter here can therefore CAUSE a kick instead of stopping one.
-- In v0.6.0 nothing is installed automatically. AC.Init only acts when the user
-- explicitly enables the aggressive mode (Settings.BacAutoBypass / SYS tab).
-- Techniques kept for opt-in use (from public working scripts):
--   1) Freeze anticheat state tables found via getgc (Phemonaz method)
--   2) Blind the movement sampler hidden behind "ContentCatalog.Runtime"
--   3) Mask executor HttpGet/HttpPost probes coming from game scripts (RISKY:
--      suspected BAC-2516 trigger — the AC probe expects to fail, we answer wrong)
--   4) Block client-side LocalPlayer:Kick (RISKY: classic honeypot target)
--   5) Optional WalkSpeed write-lock via __newindex
-- Server-side kicks never pass through Lua and cannot be blocked from the client.

local AC = {}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

AC.Status = {
    Mode = "GHOST", -- GHOST (nothing installed) or AGGRESSIVE
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
                -- Печать ТОЛЬКО в debug-режиме: warn попадает в LogService,
                -- который читается античитом (MUTE-доктрина v0.6.1).
                if StealthRef.Note then pcall(StealthRef.Note, "заблокирован клиентский Kick #" .. AC.Status.BlockedKicks) end
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
-- Init. Safe by default: GHOST mode installs NOTHING.
-- Aggressive mode (aggressive == true) arms the legacy counter-measures,
-- each one individually governed by its Settings flag.
---------------------------------------------------------------------
function AC.Init(stealth, settings, aggressive)
    StealthRef = stealth or StealthRef
    SettingsRef = settings or SettingsRef
    AC.Supported = hasExecutorCore()

    if not aggressive then
        AC.Status.Mode = "GHOST"
        AC.Status.NamecallHooked = false
        AC.Status.NewindexHooked = false
        AC.Status.StatesFrozen = 0
        AC.Status.SamplersBlinded = 0
        return false
    end

    AC.Status.Mode = "AGGRESSIVE"
    AC.InstallNamecallGuard()
    if SettingsRef.FreezeACStates ~= false then
        task.spawn(function() AC.FreezeStates() end)
    end
    if SettingsRef.BlindSamplers ~= false then
        task.spawn(function() AC.BlindSamplers() end)
    end

    -- Single deferred re-scan (AC tables appear lazily as game scripts run).
    task.spawn(function()
        task.wait(20)
        if not StealthRef or StealthRef.Aborted then return end
        if AC.Status.Mode ~= "AGGRESSIVE" then return end
        if SettingsRef.FreezeACStates ~= false then AC.FreezeStates() end
        if SettingsRef.BlindSamplers ~= false and AC.Status.SamplersBlinded == 0 then
            AC.BlindSamplers()
        end
    end)

    return AC.Supported
end

function AC.Summary()
    local s = AC.Status
    if s.Mode == "GHOST" then
        return "GHOST: хуков нет (рекомендуется) • кик-гард OFF"
    end
    return string.format(
        "AGGRESSIVE • заморожено %d • сэмплеров %d • кик-гард %s • пробы %s • хук NEWINDEX %s",
        s.StatesFrozen or 0,
        s.SamplersBlinded or 0,
        (StealthRef.BlockKick ~= false) and "ON" or "OFF",
        s.NamecallHooked and "маскированы" or "нет",
        s.NewindexHooked and "ON" or "OFF"
    )
end

return AC
