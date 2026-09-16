-- MilfaCheatHUB • Steal An Egg
-- Stable modular entry point v0.3.0.

local EXPECTED_PLACE_ID = 107778070777162
local BASE_URL = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/Steal-A-Egg/"
local VERSION = "0.3.0"

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
end

env.MilfaCheatHUBCleanup = function()
    if env.MilfaCheatHUBSession == session then
        env.MilfaCheatHUBSession = session + 1
    end
    cleanup()
end

local function loadModule(relativePath)
    local url = BASE_URL .. relativePath .. "?v=" .. VERSION
    local requestOk, source = pcall(game.HttpGet, game, url)
    if not requestOk or type(source) ~= "string" or #source < 10 then
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

local success, failure = xpcall(function()
    local Config = loadModule("modules/config.lua")
    local UI = loadModule("modules/ui.lua")
    state.Loader = UI.ShowLoader(Config)

    local function loading(progress, text)
        if state.Loader then state.Loader:Set(progress, text) end
        task.wait()
    end

    loading(0.12, game.PlaceId == EXPECTED_PLACE_ID and "Игра определена" or "Открыта другая игра")

    loading(0.25, "Загружаем сканер...")
    local Scanner = loadModule("modules/scanner.lua")
    local scanner = Scanner.new(Config)

    loading(0.35, "Проверяем Networking...")
    local Network = loadModule("modules/network.lua")
    local network = Network.new(Config)

    loading(0.42, "Определяем редкости...")
    local Rarity = loadModule("modules/rarity.lua")

    loading(0.50, "Определяем точки...")
    local Positions = loadModule("modules/positions.lua")
    local positions = Positions.new(Config, scanner)

    loading(0.58, "Подготавливаем ESP...")
    local ESP = loadModule("modules/esp.lua")
    state.ESP = ESP.new(Config, Rarity)

    loading(0.66, "Запускаем движок яиц...")
    local Eggs = loadModule("modules/eggs.lua")
    local eggs = Eggs.new(Config, scanner, network, Rarity)

    loading(0.74, "Создаём компактный GUI...")
    state.App = UI.new(Config)
    state.App:SetCloseCallback(env.MilfaCheatHUBCleanup)

    loading(0.82, "Подключаем автоматизацию...")
    local Automation = loadModule("modules/automation.lua")
    local automation = Automation.new(Config, eggs, network, positions, scanner, Rarity)

    loading(0.88, "Настраиваем персонажа...")
    local Player = loadModule("modules/player.lua")
    local player = Player.new(Config)

    loading(0.94, "Подключаем функции...")
    local Features = loadModule("modules/features.lua")
    state.Features = Features.new(Config, state.App, scanner, network, positions, state.ESP, eggs, automation, player, Rarity, alive)
    state.Features:Build()
    state.Features:Start()

    loading(1, "MilfaCheatHUB готов")
    task.wait(0.25)
    if state.Loader then
        state.Loader:Destroy()
        state.Loader = nil
    end

    print("[MilfaCheatHUB] Steal An Egg v" .. Config.Version .. " loaded")
end, debug.traceback)

if not success then
    warn("[MilfaCheatHUB] " .. tostring(failure))
    cleanup()
end

return env.MilfaCheatHUBCleanup
