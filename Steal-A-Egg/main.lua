-- MilfaCheatHUB • Steal An Egg
-- Stable modular entry point v0.5.0 (anticheat bypass).

local EXPECTED_PLACE_ID = 107778070777162
local BASE_URL = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/Steal-A-Egg/"
local VERSION = "0.5.0"

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer

local env = (getgenv and getgenv()) or _G
if env.MilfaCheatHUBCleanup then pcall(env.MilfaCheatHUBCleanup) end

env.MilfaCheatHUBSession = (env.MilfaCheatHUBSession or 0) + 1
local session = env.MilfaCheatHUBSession
local state = {
    Loader = nil,
    App = nil,
    Features = nil,
    ESP = nil,
    Cleaned = false,
}

local function alive()
    return not state.Cleaned and env.MilfaCheatHUBSession == session
end

local function cleanup()
    if state.Cleaned then return end
    state.Cleaned = true

    if state.Features then pcall(function() state.Features:Destroy() end) end
    if state.ESP then pcall(function() state.ESP:Destroy() end) end
    if state.App then pcall(function() state.App:Destroy() end) end
    if state.Loader then pcall(function() state.Loader:Destroy() end) end

    state.Features = nil
    state.ESP = nil
    state.App = nil
    state.Loader = nil
    if state.Stealth then pcall(function() state.Stealth.Shutdown() end) end
    state.Stealth = nil
end

env.MilfaCheatHUBCleanup = function()
    if env.MilfaCheatHUBSession == session then
        env.MilfaCheatHUBSession = session + 1
    end
    cleanup()
end

-- Instant panic: kills GUI, ESP, automation and restores the character.
env.MilfaPanic = env.MilfaCheatHUBCleanup

local function loadModule(relativePath)
    local url = BASE_URL .. relativePath .. "?v=" .. VERSION
    local source
    for attempt = 1, 3 do
        local requestOk, result = pcall(game.HttpGet, game, url)
        if requestOk and type(result) == "string" and #result > 10 then
            source = result
            break
        end
        if attempt < 3 then task.wait(0.35 * attempt) end
    end
    if not source then
        error("Не удалось загрузить модуль: " .. relativePath, 0)
    end

    local chunk, compileError = loadstring(source, "@MilfaCheatHUB/" .. relativePath)
    if not chunk then
        error("Ошибка кода " .. relativePath .. ": " .. tostring(compileError), 0)
    end

    local runOk, module = pcall(chunk)
    if not runOk then
        error("Ошибка запуска " .. relativePath .. ": " .. tostring(module), 0)
    end
    return module
end

-- Defined BEFORE the xpcall block. In v0.4.0 it was first used above its
-- own declaration, which crashed every launch with
-- "attempt to call a nil value" at line 79.
local function loadingStep(progress, text)
    if state.Loader and state.Loader.Set then
        pcall(state.Loader.Set, state.Loader, progress, text)
    end
    task.wait()
end

local success, failure = xpcall(function()
    local Config = loadModule("modules/config.lua")

    loadingStep(0.08, "Включаем стелс-режим...")
    local Stealth = loadModule("modules/stealth.lua")
    state.Stealth = Stealth
    Stealth.SafeTeleport = Config.Settings.SafeTeleport
    Stealth.GlideSpeed = Config.Settings.GlideSpeed
    loadingStep(0.10, "Обходим античит (BAC)...")
    local AntiCheat = loadModule("modules/anticheat.lua")
    state.AntiCheat = AntiCheat
    Stealth.AntiCheat = AntiCheat
    task.spawn(function()
        AntiCheat.Init(Stealth, Config.Settings)
        if AntiCheat.Status.NamecallHooked then
            print("[MilfaCheatHUB] Обход античита активен: кик-гард + маскировка проб + getgc")
        end
    end)

    local UI = loadModule("modules/ui.lua")
    state.Loader = UI.ShowLoader(Config, Stealth)

    loadingStep(0.12, "Стелс: " .. tostring(Stealth.MountKind) .. (game.PlaceId == EXPECTED_PLACE_ID and " • игра ок" or " • другая игра"))

    loadingStep(0.25, "Загружаем сканер...")
    local Scanner = loadModule("modules/scanner.lua")
    local scanner = Scanner.new(Config)

    loadingStep(0.30, "Проверяем Networking...")
    local Network = loadModule("modules/network.lua")
    local network = Network.new(Config)

    loadingStep(0.38, "Определяем редкости...")
    local Rarity = loadModule("modules/rarity.lua")

    loadingStep(0.46, "Определяем точки...")
    local Positions = loadModule("modules/positions.lua")
    local positions = Positions.new(Config, scanner)

    loadingStep(0.54, "Подготавливаем ESP...")
    local ESP = loadModule("modules/esp.lua")
    state.ESP = ESP.new(Config, Rarity, Stealth)

    loadingStep(0.62, "Запускаем движок яиц...")
    local Eggs = loadModule("modules/eggs.lua")
    local eggs = Eggs.new(Config, scanner, network, Rarity)

    loadingStep(0.70, "Создаём компактный GUI...")
    state.App = UI.new(Config, Stealth)
    state.App:SetCloseCallback(env.MilfaCheatHUBCleanup)

    loadingStep(0.78, "Подключаем автоматизацию...")
    local Automation = loadModule("modules/automation.lua")
    local automation = Automation.new(Config, eggs, network, positions, scanner, Rarity, Stealth)

    loadingStep(0.86, "Настраиваем персонажа...")
    local Player = loadModule("modules/player.lua")
    local player = Player.new(Config, Stealth)

    loadingStep(0.93, "Подключаем функции...")
    local Features = loadModule("modules/features.lua")
    state.Features = Features.new(Config, state.App, scanner, network, positions, state.ESP, eggs, automation, player, Rarity, alive, Stealth)
    state.Features:Build()
    state.Features:Start()

    loadingStep(1, "MilfaCheatHUB готов")
    task.wait(0.25)
    if state.Loader then
        state.Loader:Destroy()
        state.Loader = nil
    end

    print("[MilfaCheatHUB] Steal An Egg v" .. Config.Version .. " loaded (stealth: " .. tostring(Stealth.MountKind) .. ")")
end, debug.traceback)

if not success then
    warn("[MilfaCheatHUB] " .. tostring(failure))
    cleanup()
end

return env.MilfaCheatHUBCleanup
