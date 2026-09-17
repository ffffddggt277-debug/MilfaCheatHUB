-- MilfaCheatHUB • Steal An Egg
-- Silent modular entry point v0.6.2 (CALM).
--
-- Evidence timeline:
--   v0.4.0 crashed BEFORE creating any GUI or hook and STILL got kicked ~5s
--   later — the only traces were console output (LogService is readable by
--   game scripts via GetLogHistory) and getgenv keys with the word "Cheat".
--   v0.6.0 (PlayerGui GUI, zero hooks) drew BAC-7517. v0.6.1 printed one
--   line containing the word "GUI" — still a LogHistory keyword.
-- v0.6.2 ships CALM:
--   * the ONLY console output is the bare version number (no words at all)
--   * session state lives in getgenv under ONE random key, no signature words
--   * GUI mounts IMMEDIATELY (HeadlessLoad=false default): visible GUI with
--     zero hooks is exactly the profile of scripts that survive in this game;
--     mount is hidden-first (gethui/CoreGui), PlayerGui only as last resort
--   * HeadlessLoad=true stays available as an opt-in (summon: 3-finger tap /
--     RightControl / chat command)

local EXPECTED_PLACE_ID = 107778070777162
local BASE_URL = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/Steal-A-Egg/"
local VERSION = "0.6.3"

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
repeat task.wait() until Players.LocalPlayer
local LocalPlayer = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G

-- Wipe legacy signature keys left by older versions (they persist in getgenv
-- for the whole server session and are readable by keyword scans).
do
    local legacy = {
        "MilfaCheatHUBSession", "MilfaCheatHUBCleanup", "MilfaPanic",
        "MilfaDiagnostics", "MilfaCheatHUBIconAsset", "MilfaCheatHUBIconLoading",
    }
    if env.MilfaCheatHUBCleanup then pcall(env.MilfaCheatHUBCleanup) end
    for _, key in ipairs(legacy) do
        pcall(function() env[key] = nil end)
    end
end

-- Orphan cleanup: previous MUTE sessions live under random MH<key> tables
-- marked with __mh. Kill their leftovers, then drop the keys entirely.
do
    for key, value in pairs(env) do
        if type(key) == "string" and type(value) == "table" and value.__mh then
            if value.Cleanup then pcall(value.Cleanup) end
            pcall(function() env[key] = nil end)
        end
    end
end

-- Random registry key: new every run, no dictionary words, nothing to grep for.
local RANDOM_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"
math.randomseed(os.time() + math.floor(os.clock() * 100000))
local function randomString(length)
    local out = {}
    for _ = 1, length do
        local index = math.random(1, #RANDOM_ALPHABET)
        out[#out + 1] = RANDOM_ALPHABET:sub(index, index)
    end
    return table.concat(out)
end

local REGISTRY_KEY = "MH" .. randomString(8)
local reg = { __mh = true, Key = REGISTRY_KEY, Version = VERSION }
env[REGISTRY_KEY] = reg

reg.Session = (reg.Session or 0) + 1
local session = reg.Session

local state = {
    Loader = nil,
    App = nil,
    Features = nil,
    ESP = nil,
    Connections = {},
    WorldBuilt = false,
    Cleaned = false,
}

-- Loaded lazily / assigned during startup.
local Config, Stealth, AntiCheat, UI, Features
local ScannerM, NetworkM, RarityM, PositionsM, ESPM, EggsM, AutomationM, PlayerM

local DEBUG = false
local function log(...)
    if DEBUG then print("[mh]", ...) end
end

local function alive()
    return not state.Cleaned and reg.Session == session
end

local function disconnectAll()
    for _, connection in ipairs(state.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    state.Connections = {}
end

local function cleanup()
    if state.Cleaned then return end
    state.Cleaned = true

    if state.Features then pcall(function() state.Features:Destroy() end) end
    -- Headless edge case: мир собран, но UI не успел — чистим напрямую.
    if state.Automation and state.Automation.Destroy then pcall(function() state.Automation:Destroy() end) end
    if state.Player and state.Player.Destroy then pcall(function() state.Player:Destroy() end) end
    if state.ESP then pcall(function() state.ESP:Destroy() end) end
    if state.App then pcall(function() state.App:Destroy() end) end
    if state.Loader then pcall(function() state.Loader:Destroy() end) end
    disconnectAll()
    if Stealth then pcall(function() Stealth.Shutdown() end) end

    state.Features = nil
    state.ESP = nil
    state.App = nil
    state.Loader = nil
    state.Automation = nil
    state.Player = nil
end

reg.Cleanup = function()
    if reg.Session == session then reg.Session = session + 1 end
    cleanup()
    env[REGISTRY_KEY] = nil
end
reg.Panic = reg.Cleanup

-- Bundle sources MUST be declared BEFORE loadModule: otherwise loadModule
-- resolves the name as a global (always nil) and silently falls back to
-- 14 per-file fetches. This exact bug shipped in v0.6.0.
local bundleSources

local function loadModule(relativePath)
    local source
    if bundleSources and type(bundleSources[relativePath]) == "string" then
        source = bundleSources[relativePath]
    else
        local url = BASE_URL .. relativePath .. "?v=" .. VERSION
        for attempt = 1, 3 do
            local requestOk, result = pcall(game.HttpGet, game, url)
            if requestOk and type(result) == "string" and #result > 10 then
                source = result
                break
            end
            if attempt < 3 then task.wait(0.35 * attempt) end
        end
    end
    if not source then
        error("Не удалось загрузить модуль: " .. relativePath, 0)
    end

    -- Neutral chunk name: no repo words, nothing for keyword scans to bite.
    local chunk, compileError = loadstring(source, "@mh/" .. relativePath)
    if not chunk then
        error("Ошибка кода " .. relativePath .. ": " .. tostring(compileError), 0)
    end

    local runOk, module = pcall(chunk)
    if not runOk then
        error("Ошибка запуска " .. relativePath .. ": " .. tostring(module), 0)
    end
    return module
end

-- GHOST network profile: ONE request for all modules. Silent fallback to
-- per-module fetches keeps the loader working during rollouts.
local function loadBundle()
    local requestOk, result = pcall(game.HttpGet, game, BASE_URL .. "bundle.lua?v=" .. VERSION)
    if not requestOk or type(result) ~= "string" or #result < 50 then return false end
    local chunk, err = loadstring(result, "@mh/bundle.lua")
    if not chunk then return false end
    local runOk, table_ = pcall(chunk)
    if not runOk or type(table_) ~= "table" then return false end
    bundleSources = table_
    return true
end

-- Defined BEFORE the xpcall block (v0.4.0 regression guard).
local function loadingStep(progress, text)
    if state.Loader and state.Loader.Set then
        pcall(state.Loader.Set, state.Loader, progress, text)
    end
    task.wait()
end

-- Builds every engine instance (scanner, network, eggs, automation...). No UI,
-- no loops here. Used by the classic path immediately and by the headless path
-- on first GUI summon.
local function buildWorld()
    if state.WorldBuilt then return true end

    loadingStep(0.25, "Загружаем сканер...")
    local scanner = ScannerM.new(Config)

    loadingStep(0.30, "Проверяем Networking...")
    local network = NetworkM.new(Config)

    loadingStep(0.38, "Определяем редкости...")
    local rarity = RarityM

    loadingStep(0.46, "Определяем точки...")
    local positions = PositionsM.new(Config, scanner)

    loadingStep(0.54, "Подготавливаем ESP...")
    state.ESP = ESPM.new(Config, rarity, Stealth)

    loadingStep(0.62, "Запускаем движок яиц...")
    local eggs = EggsM.new(Config, scanner, network, rarity)

    loadingStep(0.78, "Подключаем автоматизацию...")
    local automation = AutomationM.new(Config, eggs, network, positions, scanner, rarity, Stealth)
    state.Automation = automation

    loadingStep(0.86, "Настраиваем персонажа...")
    local player = PlayerM.new(Config, Stealth)
    state.Player = player

    state.Scanner = scanner
    state.Network = network
    state.Positions = positions
    state.Eggs = eggs
    state.WorldBuilt = true
    return true
end

-- GUI summon: first call builds the interface (lazy), later calls toggle it.
local function summonGui()
    if not alive() then return end
    if state.App then
        pcall(function() state.App:ToggleVisibility() end)
        return
    end

    local ok, err = pcall(function()
        buildWorld()

        loadingStep(0.70, "Создаём компактный GUI...")
        state.App = UI.new(Config, Stealth)
        state.App:SetCloseCallback(reg.Cleanup)

        loadingStep(0.93, "Подключаем функции...")
        state.Features = Features.new(Config, state.App, state.Scanner, state.Network,
            state.Positions, state.ESP, state.Eggs, state.Automation, state.Player,
            RarityM, alive, Stealth)
        state.Features:Build()
        state.Features:Start()

        pcall(function() state.App:Show() end)
    end)
    if not ok then
        log("gui: " .. tostring(err))
    end
end
reg.Show = summonGui

reg.Diag = function()
    print("[mh] diag v" .. VERSION)
    print("  key: " .. REGISTRY_KEY)
    print("  mount: " .. tostring(Stealth and Stealth.MountKind or "none"))
    print("  bac: " .. tostring(AntiCheat and AntiCheat.Summary and AntiCheat.Summary() or "n/a"))
    print("  headless: " .. tostring(Config and Config.Settings.HeadlessLoad))
    print("  world: " .. tostring(state.WorldBuilt))
    if Stealth and Stealth.FindAntiCheatScripts then
        local found = Stealth.FindAntiCheatScripts()
        print("  ac candidates (" .. #found .. "):")
        for _, script_ in ipairs(found) do
            print("    - " .. script_.GetFullName())
        end
    end
end

local success, failure = xpcall(function()
    local bundleOk = loadBundle()

    Config = loadModule("modules/config.lua")
    DEBUG = Config.Settings.DebugLogs == true

    loadingStep(0.08, "Тихий режим...")
    Stealth = loadModule("modules/stealth.lua")
    state.Stealth = Stealth
    Stealth.SafeTeleport = Config.Settings.SafeTeleport
    Stealth.GlideSpeed = Config.Settings.GlideSpeed
    Stealth.GuiMount = Config.Settings.GuiMount or "Hidden"
    Stealth.Debug = DEBUG
    Stealth.Registry = reg

    loadingStep(0.10, "Режим MUTE (без хуков)...")
    AntiCheat = loadModule("modules/anticheat.lua")
    state.AntiCheat = AntiCheat
    Stealth.AntiCheat = AntiCheat
    task.spawn(function()
        -- MUTE: NOTHING is hooked unless the user explicitly opts in.
        AntiCheat.Init(Stealth, Config.Settings, Config.Settings.BacAutoBypass == true)
    end)

    -- Module sources are pulled up-front (bundle makes this one fetch); heavy
    -- instances are built later by buildWorld().
    UI = loadModule("modules/ui.lua")
    Features = loadModule("modules/features.lua")
    ScannerM = loadModule("modules/scanner.lua")
    NetworkM = loadModule("modules/network.lua")
    RarityM = loadModule("modules/rarity.lua")
    PositionsM = loadModule("modules/positions.lua")
    ESPM = loadModule("modules/esp.lua")
    EggsM = loadModule("modules/eggs.lua")
    AutomationM = loadModule("modules/automation.lua")
    PlayerM = loadModule("modules/player.lua")

    if Config.Settings.HeadlessLoad ~= false then
        -- MUTE headless: no GUI, no loader, no instances, no loops. The only
        -- artifact in this game session is one bare version number — no words
        -- for a LogHistory keyword scan to bite.
        print(VERSION)
    else
        -- Classic path (default): loader window + immediate build. No text is
        -- printed; the visible window itself is the load confirmation.
        state.Loader = UI.ShowLoader(Config, Stealth)
        loadingStep(0.12, "CALM: " .. tostring(Stealth.GuiMount) .. (bundleOk and " • bundle" or " • файлы") .. (game.PlaceId == EXPECTED_PLACE_ID and " • игра ок" or " • другая игра"))

        buildWorld()

        loadingStep(0.70, "Создаём компактный GUI...")
        state.App = UI.new(Config, Stealth)
        state.App:SetCloseCallback(reg.Cleanup)

        loadingStep(0.93, "Подключаем функции...")
        state.Features = Features.new(Config, state.App, state.Scanner, state.Network,
            state.Positions, state.ESP, state.Eggs, state.Automation, state.Player,
            RarityM, alive, Stealth)
        state.Features:Build()
        state.Features:Start()

        loadingStep(1, "Готово")
        task.wait(0.25)
        if state.Loader then
            state.Loader:Destroy()
            state.Loader = nil
        end
        print(Config.Version)
    end

    -- Summon triggers make sense ONLY in headless mode (GUI already exists in
    -- the classic path). Keyboard is handled inside UI.new.
    if Config.Settings.HeadlessLoad ~= false then
        table.insert(state.Connections, UserInputService.TouchTap:Connect(function(touchPositions, processed)
            if processed then return end
            if #touchPositions >= 3 then summonGui() end
        end))
        table.insert(state.Connections, LocalPlayer.Chatted:Connect(function(message)
            local wanted = string.lower((Config and Config.Settings.ChatCommand) or "/e mh")
            local msg = string.lower(message)
            if msg == wanted or msg == "/e mh" or msg == "mh" or msg == "/e m" then
                summonGui()
            end
        end))
    end

    -- Silent survival heartbeat: with DebugLogs the user can see how long the
    -- session lives; the scanner cycle runs every ~5 seconds, so these markers
    -- bracket the kill window for diagnostics.
    reg.LoadedAt = os.clock()
    task.spawn(function()
        for _, mark in ipairs({ 10, 30, 60, 180 }) do
            local left = mark - (os.clock() - reg.LoadedAt)
            if left > 0 then task.wait(left) end
            if not alive() then return end
            log("t+" .. mark .. "s alive")
        end
    end)
end, debug.traceback)

if not success then
    -- Neutral tag, no signature words; details only in debug mode.
    warn("mh err: " .. tostring(failure))
    if DEBUG then print("mh " .. debug.traceback(failure)) end
    cleanup()
end

return reg.Cleanup
