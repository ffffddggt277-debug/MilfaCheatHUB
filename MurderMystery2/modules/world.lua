-- MilfaCheatHUB • Murder Mystery 2
-- World/round watcher v0.3.0.
--
-- Проверено по рабочим скриптам (KittyHub/W-Azeox/R3TH):
--   * карта = Model в workspace с CoinContainer (имя НЕ "Lobby"); лобби тоже
--     имеет CoinContainer — различаем по списку карт;
--   * монеты: Model "Coin_Server" с CoinVisual.MainCoin ЛИБО голый BasePart;
--   * GunDrop — BasePart где угодно в workspace (появляется при смерти
--     шерифа), ловим DescendantAdded + рекурсивный поиск;
--   * таймер: Remotes.Extras.GetTimer (RemoteFunction, секунды) и/или
--     workspace.RoundTimerPart атрибут Time — пробуем оба канала.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = {}

World.CurrentMap = nil
World.GunDrop = nil
World.TimerRemote = nil
World.Debug = false

local connections = {}
local gunDropCallbacks = {}
local mapCallbacks = {}

local function note(...)
    if World.Debug then print("[mh world]", ...) end
end

---------------------------------------------------------------------
-- Map detection
---------------------------------------------------------------------

local function hasCoinContainer(model)
    local ok, found = pcall(function() return model:FindFirstChild("CoinContainer") end)
    return ok and found ~= nil
end

local function hasSpawns(model)
    local ok, found = pcall(function()
        return model:FindFirstChild("Spawns") or model:FindFirstChild("Spawn")
    end)
    return ok and found ~= nil
end

-- Карта раунда: НЕ лобби, содержит CoinContainer и/или Spawns.
local function looksLikeMap(model)
    if not model or not model:IsA("Model") then return false end
    if model.Name == "Lobby" then return false end
    return hasCoinContainer(model) or hasSpawns(model)
end

local function scanForMap()
    for _, child in ipairs(Workspace:GetChildren()) do
        if looksLikeMap(child) then
            return child
        end
    end
    return nil
end

function World.GetMap()
    if World.CurrentMap and World.CurrentMap.Parent then
        return World.CurrentMap
    end
    local found = scanForMap()
    if found then
        World.CurrentMap = found
        note("map found: " .. found.Name)
        for _, callback in ipairs(mapCallbacks) do pcall(callback, found) end
    end
    return found
end

function World.GetLobby()
    local ok, lobby = pcall(function() return Workspace:FindFirstChild("Lobby") end)
    return ok and lobby or nil
end

function World.IsInRound()
    return World.GetMap() ~= nil
end

-- Таймер в два канала: сначала родной ремоут, затем атрибут RoundTimerPart.
function World.GetTimer()
    if not World.TimerRemote or not World.TimerRemote.Parent then
        pcall(function()
            World.TimerRemote = ReplicatedStorage:FindFirstChild("GetTimer", true)
        end)
    end
    if World.TimerRemote then
        local ok, seconds = pcall(function() return World.TimerRemote:InvokeServer() end)
        if ok and type(seconds) == "number" then return seconds end
    end
    -- Fallback: workspace.RoundTimerPart:GetAttribute("Time")
    local ok, value = pcall(function()
        local part = Workspace:FindFirstChild("RoundTimerPart")
        return part and part:GetAttribute("Time") or nil
    end)
    if ok and type(value) == "number" then return value end
    return nil
end

-- Центр карты для телепортов: bounding box модели.
function World.GetMapCenter()
    local map = World.GetMap()
    if not map then return nil end
    local ok, center = pcall(function()
        return map:GetBoundingBox().Position
    end)
    if ok and center then return center end
    return nil
end

-- Позиция спавна в лобби (ресёрч: ~(14.7, 505.2, -61.3)).
function World.GetLobbyPosition()
    local lobby = World.GetLobby()
    local spawns = lobby and (lobby:FindFirstChild("Spawns") or lobby:FindFirstChild("Spawn"))
    if spawns then
        local base = spawns:IsA("BasePart") and spawns or spawns:FindFirstChildWhichIsA("BasePart", true)
        if base then
            return base.Position + Vector3.new(0, 3, 0)
        end
    end
    return Vector3.new(14.72, 506.2, -61.29)
end

-- Спавн карты раунда (первый Spawn/PlayerSpawn в потомках).
function World.GetMapSpawn()
    local map = World.GetMap()
    if not map then return nil end
    local spawns = map:FindFirstChild("Spawns") or map:FindFirstChild("Spawn")
    if spawns then
        local base = spawns:IsA("BasePart") and spawns or spawns:FindFirstChildWhichIsA("BasePart", true)
        if base then return base.Position + Vector3.new(0, 3.5, 0) end
    end
    pcall(function()
        for _, descendant in ipairs(map:GetDescendants()) do
            if descendant:IsA("BasePart") and (descendant.Name == "Spawn" or descendant.Name == "PlayerSpawn") then
                spawns = descendant
                break
            end
        end
    end)
    if spawns and spawns:IsA("BasePart") then return spawns.Position + Vector3.new(0, 3.5, 0) end
    local center = World.GetMapCenter()
    if center then return center + Vector3.new(0, 6, 0) end
    return nil
end

---------------------------------------------------------------------
-- Coins
---------------------------------------------------------------------

-- Часть монеты: голый BasePart или Model(Coin_Server)/CoinVisual/MainCoin.
local function coinPart(obj)
    if obj:IsA("BasePart") then return obj end
    local ok, result = pcall(function()
        local visual = obj:FindFirstChild("CoinVisual")
        if visual then
            local main = visual:FindFirstChild("MainCoin")
            if main and main:IsA("BasePart") then return main end
        end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end)
    return ok and result or nil
end

-- Собираем монеты; includeLobby добавляет монеты лобби.
function World.FindCoins(includeLobby)
    local coins = {}
    local function harvest(container)
        if not container then return end
        for _, coin in ipairs(container:GetChildren()) do
            local lowered = string.lower(coin.Name)
            if string.find(lowered, "coin", 1, true) then
                local collected = false
                pcall(function() collected = coin:GetAttribute("Collected") == true end)
                if not collected then
                    local part = coinPart(coin)
                    if part then coins[#coins + 1] = part end
                end
            end
        end
    end

    pcall(function()
        local map = World.GetMap()
        if map then harvest(map:FindFirstChild("CoinContainer")) end
        if includeLobby then
            local lobby = World.GetLobby()
            if lobby then harvest(lobby:FindFirstChild("CoinContainer")) end
        end
    end)
    return coins
end

---------------------------------------------------------------------
-- GunDrop watcher
---------------------------------------------------------------------

function World.GetGunDrop()
    if World.GunDrop and World.GunDrop.Parent then
        return World.GunDrop
    end
    local found
    pcall(function() found = Workspace:FindFirstChild("GunDrop", true) end)
    if found then World.GunDrop = found end
    return found
end

function World.OnGunDrop(callback)
    gunDropCallbacks[#gunDropCallbacks + 1] = callback
end

function World.OnMap(callback)
    mapCallbacks[#mapCallbacks + 1] = callback
end

---------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------

function World.Start()
    if World._started then return end
    World._started = true

    -- GunDrop появляется где угодно: следим за потомками.
    connections[#connections + 1] = Workspace.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "GunDrop" then
            World.GunDrop = descendant
            note("GunDrop spawned")
            for _, callback in ipairs(gunDropCallbacks) do pcall(callback, descendant) end
            task.spawn(function()
                while descendant and descendant.Parent do task.wait(0.5) end
                if World.GunDrop == descendant then World.GunDrop = nil end
            end)
        end
    end)

    -- Границы раунда: появление/удаление карты.
    connections[#connections + 1] = Workspace.ChildAdded:Connect(function(child)
        if looksLikeMap(child) then
            World.CurrentMap = child
            note("map added: " .. child.Name)
            for _, callback in ipairs(mapCallbacks) do pcall(callback, child) end
        end
    end)
    connections[#connections + 1] = Workspace.ChildRemoved:Connect(function(child)
        if child == World.CurrentMap then
            World.CurrentMap = nil
            note("map removed")
        end
        -- GunDrop живёт внутри карты: карта удалена — пистолет тоже мёртв
        if child == World.GunDrop or (World.GunDrop and not World.GunDrop.Parent) then
            World.GunDrop = nil
        end
    end)

    task.spawn(function()
        if not game:IsLoaded() then game.Loaded:Wait() end
        task.wait(2)
        World.GetMap()
        World.GetGunDrop()
    end)
end

function World.Destroy()
    World._started = false
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
    World.CurrentMap = nil
    World.GunDrop = nil
end

return World
