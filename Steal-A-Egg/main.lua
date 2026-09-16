-- MilfaCheatHUB • Steal An Egg
-- Main entry point for the modular build.

local EXPECTED_PLACE_ID = 107778070777162
local BASE_URL = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/Steal-A-Egg/"

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer

local environment = (getgenv and getgenv()) or _G
if environment.MilfaCheatHUBCleanup then
    pcall(environment.MilfaCheatHUBCleanup)
end

environment.MilfaCheatHUBSession = (environment.MilfaCheatHUBSession or 0) + 1
local session = environment.MilfaCheatHUBSession
local function alive()
    return environment.MilfaCheatHUBSession == session
end

local function loadModule(relativePath)
    local url = BASE_URL .. relativePath .. "?v=0.1.0"
    local ok, source = pcall(game.HttpGet, game, url)
    assert(ok and type(source) == "string", "Не удалось загрузить " .. relativePath)

    local chunk, compileError = loadstring(source, "@MilfaCheatHUB/" .. relativePath)
    assert(chunk, "Ошибка модуля " .. relativePath .. ": " .. tostring(compileError))

    local success, module = pcall(chunk)
    assert(success, "Ошибка запуска " .. relativePath .. ": " .. tostring(module))
    return module
end

local Config = loadModule("modules/config.lua")
local UI = loadModule("modules/ui.lua")
local loader = UI.ShowLoader(Config)

local function loading(progress, text)
    loader:Set(progress, text)
    task.wait(0.08)
end

loading(0.12, "Проверяем игру...")
if game.PlaceId ~= EXPECTED_PLACE_ID then
    loading(0.18, "Внимание: открыта другая игра")
    task.wait(0.8)
end

loading(0.28, "Загружаем сканер...")
local Scanner = loadModule("modules/scanner.lua")
local scanner = Scanner.new(Config)

loading(0.43, "Проверяем Networking...")
local Network = loadModule("modules/network.lua")
local network = Network.new(Config)

loading(0.57, "Определяем динамические точки...")
local Positions = loadModule("modules/positions.lua")
local positions = Positions.new(Config, scanner)

loading(0.70, "Подготавливаем неоновый ESP...")
local ESP = loadModule("modules/esp.lua")
local esp = ESP.new(Config)

loading(0.82, "Создаём MilfaCheatHUB...")
local app = UI.new(Config)

loading(0.93, "Подключаем функции...")
local Features = loadModule("modules/features.lua")
local features = Features.new(Config, app, scanner, network, positions, esp, alive)
features:Build()
features:Start()

loading(1, "MilfaCheatHUB готов")
task.wait(0.55)
loader:Destroy()

local cleaned = false
local function cleanup()
    if cleaned then return end
    cleaned = true
    if features then pcall(function() features:Destroy() end) end
    if esp then pcall(function() esp:Destroy() end) end
    if app then pcall(function() app:Destroy() end) end
end

environment.MilfaCheatHUBCleanup = function()
    if environment.MilfaCheatHUBSession == session then
        environment.MilfaCheatHUBSession = session + 1
    end
    cleanup()
end

print("[MilfaCheatHUB] Steal An Egg v" .. Config.Version .. " loaded")
return environment.MilfaCheatHUBCleanup
