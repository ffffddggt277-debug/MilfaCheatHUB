-- MilfaCheatHUB • Murder Mystery 2
-- Silent modular entry point v0.1.0 (CALM).
--
-- Same doctrine as Steal-A-Egg v0.6.2 (proven load profile):
--   * the ONLY console output is the bare version number (no words — the log
--     is readable by game scripts via GetLogHistory);
--   * session state lives in getgenv under ONE random key, no signature words;
--   * GUI mounts IMMEDIATELY (HeadlessLoad=false default), hidden-first
--     (gethui/CoreGui), PlayerGui only as last resort;
--   * zero hooks at load; everything aggressive stays opt-in;
--   * HeadlessLoad=true summons via 3-finger tap / RightControl / chat.

local EXPECTED_PLACE_ID = 142823291
local BASE_URL = "https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/MurderMystery2/"
local VERSION = "0.5.0"

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
repeat task.wait() until Players.LocalPlayer
local LocalPlayer = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G

-- Wipe legacy signature keys left by older versions.
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

-- Orphan cleanup: previous sessions live under random MH<key> tables marked __mh.
do
    for key, value in pairs(env) do
        if type(key) == "string" and type(value) == "table" and value.__mh then
            if value.Cleanup then pcall(value.Cleanup) end
            pcall(function() env[key] = nil end)
        end
    end
end

-- Random registry key: new every run, no dictionary words.
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

local Config, Stealth, AntiCheat, UI, Features
local RolesM, NetworkM, WorldM, ESPM, FarmM, CombatM, MovementM, VisualsM
local TrollM, BetaM

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
    if state.ESP then pcall(function() state.ESP:Destroy() end) end
    if state.App then pcall(function() state.App:Destroy() end) end
    if state.Loader then pcall(function() state.Loader:Destroy() end) end
    disconnectAll()
    if TrollM then pcall(function() TrollM.Shutdown() end) end
    if Stealth then pcall(function() Stealth.Shutdown() end) end

    state.Features = nil
    state.ESP = nil
    state.App = nil
    state.Loader = nil
end

reg.Cleanup = function()
    if reg.Session == session then reg.Session = session + 1 end
    cleanup()
    env[REGISTRY_KEY] = nil
end
reg.Panic = reg.Cleanup

-- Bundle sources MUST be declared BEFORE loadModule (v0.6.0 regression guard).
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

-- CALM network profile: ONE request for all modules.
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

local function loadingStep(progress, text)
    if state.Loader and state.Loader.Set then
        pcall(state.Loader.Set, state.Loader, progress, text)
    end
    task.wait()
end

-- Builds every engine instance. No UI, no aggressive counters here.
local function buildWorld()
    if state.WorldBuilt then return true end

    loadingStep(0.22, "Определяем роли...")
    local roles = RolesM
    roles.Debug = DEBUG

    loadingStep(0.30, "Проверяем Networking...")
    local network = NetworkM.new(Config)
    state.Network = network

    loadingStep(0.40, "Сканируем мир...")
    local world = WorldM
    world.Debug = DEBUG
    world.Start()
    state.World = world

    loadingStep(0.50, "Готовим ESP...")
    ESPM.Configure(Config, roles, world, Stealth)
    local esp = ESPM
    state.ESP = esp

    loadingStep(0.60, "Настраиваем фарм...")
    local farm = FarmM
    farm.Configure(Config, world, Stealth)
    state.Farm = farm

    loadingStep(0.70, "Настраиваем бой...")
    local combat = CombatM
    combat.Configure(Config, roles, Stealth)
    state.Combat = combat

    loadingStep(0.80, "Настраиваем движение...")
    local movement = MovementM
    movement.Configure(Config, Stealth)
    movement.WorldRef = world
    state.Movement = movement

    loadingStep(0.88, "Настраиваем визуал...")
    local visuals = VisualsM
    visuals.Configure(Config)
    state.Visuals = visuals

    loadingStep(0.92, "Настраиваем троллинг и бету...")
    TrollM.Configure(Config, Stealth)
    BetaM.Configure(Config, RolesM, WorldM)

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
        state.Features = Features.new(Config, state.App, RolesM, state.Network, state.World,
            state.ESP, state.Farm, state.Combat, state.Movement, state.Visuals, alive, Stealth, TrollM, BetaM)
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
    print("  headless: " .. tostring(Config and Config.Settings.HeadlessLoad))
    print("  world: " .. tostring(state.WorldBuilt))
    if RolesM then
        local murderer = RolesM.FindByRole("Murderer")
        local sheriff = RolesM.FindByRole("Sheriff")
        print("  murderer: " .. table.concat(murderer, ", ") .. (next(RolesM.Cache) == nil and " (кэш пуст — жди раунд)" or ""))
        print("  sheriff: " .. table.concat(sheriff, ", "))
        print("  remotes: " .. tostring(RolesM.RemotesFound or "не проверялись"))
        print("  localRole: " .. tostring(RolesM.LocalRole or "?"))
    end
    if WorldM then
        local map = WorldM.GetMap()
        print("  map: " .. tostring(map and map.Name or "нет"))
        print("  timer: " .. tostring(WorldM.GetTimer() or "n/a"))
        print("  gundrop: " .. tostring(WorldM.GetGunDrop() ~= nil))
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

    loadingStep(0.10, "Режим CALM (без хуков)...")
    AntiCheat = loadModule("modules/anticheat.lua")
    state.AntiCheat = AntiCheat
    Stealth.AntiCheat = AntiCheat
    task.spawn(function()
        -- CALM: NOTHING is hooked unless the user explicitly opts in.
        AntiCheat.Init(Stealth, Config.Settings, Config.Settings.BacAutoBypass == true)
    end)

    RolesM = loadModule("modules/roles.lua")
    NetworkM = loadModule("modules/network.lua")
    WorldM = loadModule("modules/world.lua")
    ESPM = loadModule("modules/mm2esp.lua")
    FarmM = loadModule("modules/farm.lua")
    CombatM = loadModule("modules/combat.lua")
    MovementM = loadModule("modules/movement.lua")
    VisualsM = loadModule("modules/visuals.lua")
    TrollM = loadModule("modules/troll.lua")
    BetaM = loadModule("modules/beta.lua")
    UI = loadModule("modules/ui.lua")
    Features = loadModule("modules/features.lua")

    if Config.Settings.HeadlessLoad ~= false then
        -- Headless: no GUI, no loops; summon via 3-finger tap / RightControl / chat.
        print(VERSION)
    else
        -- Classic path (default): loader window + immediate build.
        state.Loader = UI.ShowLoader(Config, Stealth)
        loadingStep(0.12, "CALM: " .. tostring(Stealth.GuiMount) .. (bundleOk and " • bundle" or " • файлы") .. (game.PlaceId == EXPECTED_PLACE_ID and " • игра ок" or " • другая игра"))

        buildWorld()

        loadingStep(0.70, "Создаём компактный GUI...")
        state.App = UI.new(Config, Stealth)
        state.App:SetCloseCallback(reg.Cleanup)

        loadingStep(0.93, "Подключаем функции...")
        state.Features = Features.new(Config, state.App, RolesM, state.Network, state.World,
            state.ESP, state.Farm, state.Combat, state.Movement, state.Visuals, alive, Stealth, TrollM, BetaM)
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

    -- Summon triggers make sense ONLY in headless mode.
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

    -- Silent survival heartbeat (visible only with DebugLogs).
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
    warn("mh err: " .. tostring(failure))
    if DEBUG then print("mh " .. debug.traceback(failure)) end
    cleanup()
end

return reg.Cleanup
