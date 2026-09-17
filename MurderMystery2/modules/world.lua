-- MilfaCheatHUB • Murder Mystery 2
-- World/round watcher v0.1.0.
--
-- Facts from research (FINDINGS_MM2.md):
--   * a round map is a workspace Model containing CoinContainer and/or Spawns
--     (workspace.Lobby is NOT a round map);
--   * coins live in <map>.CoinContainer, parts named "Coin_Server" carrying a
--     TouchTransmitter and an attribute Collected;
--   * a dropped sheriff gun spawns as a BasePart named "GunDrop" (anywhere in
--     workspace) — watched through DescendantAdded;
--   * round timer: Remotes.Extras.GetTimer (RemoteFunction, seconds left);
--   * lobby: workspace.Lobby (Y ≈ 505).

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

local function looksLikeMap(model)
    if not model or not model:IsA("Model") then return false end
    if model.Name == "Lobby" then return false end
    if model:FindFirstChild("CoinContainer") then return true end
    if model:FindFirstChild("Spawns") or model:FindFirstChild("Spawn") then return true end
    if model:FindFirstChild("Base") or model:FindFirstChild("Map") then return true end
    return false
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
    local map = World.GetMap()
    if not map then return false end
    local timer = World.GetTimer()
    if timer == nil then return true end
    return timer > 1
end

function World.GetTimer()
    if not World.TimerRemote then
        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            local extras = remotes and remotes:FindFirstChild("Extras")
            World.TimerRemote = extras and extras:FindFirstChild("GetTimer") or nil
            if not World.TimerRemote then
                World.TimerRemote = ReplicatedStorage:FindFirstChild("GetTimer") or nil
            end
        end)
    end
    if not World.TimerRemote then return nil end
    local ok, seconds = pcall(function() return World.TimerRemote:InvokeServer() end)
    if ok and type(seconds) == "number" then return seconds end
    return nil
end

-- Map center for teleports: bounding box of the map model.
function World.GetMapCenter()
    local map = World.GetMap()
    if not map then return nil end
    local ok, center, size = pcall(function()
        local bounds = map:GetBoundingBox()
        return bounds.Position, bounds.Size
    end)
    if ok and center then
        return center, size
    end
    return nil
end

-- Lobby spawn position (research: ~(14.7, 505.2, -61.3)).
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

-- Round map spawn position (first Spawn/PlayerSpawn descendant).
function World.GetMapSpawn()
    local map = World.GetMap()
    if not map then return nil end
    local found = nil
    pcall(function()
        for _, descendant in ipairs(map:GetDescendants()) do
            if descendant:IsA("BasePart") and (descendant.Name == "Spawn" or descendant.Name == "PlayerSpawn") then
                found = descendant
                break
            end
        end
    end)
    if found then return found.Position + Vector3.new(0, 3.5, 0) end
    local center = World.GetMapCenter()
    if center then return center + Vector3.new(0, 6, 0) end
    return nil
end

---------------------------------------------------------------------
-- Coins
---------------------------------------------------------------------

-- Collect reachable coins. `includeLobby` adds lobby coins (they exist too).
function World.FindCoins(includeLobby)
    local coins = {}
    local character = nil
    pcall(function()
        local player = game:GetService("Players").LocalPlayer
        character = player and player.Character
    end)

    local function harvest(container)
        if not container then return end
        for _, coin in ipairs(container:GetChildren()) do
            if coin.Name == "Coin_Server" then
                local collected = false
                pcall(function() collected = coin:GetAttribute("Collected") == true end)
                if not collected then
                    local part = coin:IsA("BasePart") and coin or coin:FindFirstChildWhichIsA("BasePart", true)
                    if part then
                        coins[#coins + 1] = part
                    end
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
    local found = nil
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

    -- GunDrop appears anywhere: watch descendants.
    connections[#connections + 1] = Workspace.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "GunDrop" then
            World.GunDrop = descendant
            note("GunDrop spawned")
            for _, callback in ipairs(gunDropCallbacks) do pcall(callback, descendant) end
            -- auto-clear when removed
            task.spawn(function()
                while descendant and descendant.Parent do task.wait(0.5) end
                if World.GunDrop == descendant then World.GunDrop = nil end
            end)
        end
    end)

    -- Map round boundaries.
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
        if child == World.GunDrop then World.GunDrop = nil end
    end)

    -- Initial scan once the game replicated.
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
