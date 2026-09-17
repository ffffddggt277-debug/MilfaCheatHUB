-- MilfaCheatHUB • Murder Mystery 2
-- Coin magnet + coin farm v0.1.0.
--
-- Mechanics (verified from working hubs):
--   * coins: <map>.CoinContainer children named "Coin_Server", BasePart (or
--     Model with a BasePart inside), attribute Collected marks them done;
--   * collection is a TOUCH event: firetouchinterest(hrp, coin, 0/1) counts
--     without moving; executors without firetouchinterest fall back to a tiny
--     CFrame nudge over the coin (also a touch);
--   * the server reports the bag through Remotes.Gameplay.CoinCollected
--     OnClientEvent(player, currentCoins, maxCoins); a full bag is a soft
--     limit — StopOnFull pauses, LobbyOnFull glides to the lobby.
-- Farm modes: Teleport (glide to coin), Smooth (CFrame lerp steps), Walk
-- (Humanoid:MoveTo). All delays humanized.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Farm = {}

Farm.Enabled = false          -- CoinFarm toggle
Farm.MagnetEnabled = false    -- CoinMagnet toggle
Farm.CoinsCollected = 0
Farm.BagCur = nil
Farm.BagMax = nil
Farm.Status = "выключено"
Farm.Debug = false

local ConfigRef = nil
local WorldRef = nil
local StealthRef = nil

local running = false
local loopThread = nil
local coinEvent = nil

local function note(...)
    if Farm.Debug then print("[mh farm]", ...) end
end

local function getRoot()
    local player = Players.LocalPlayer
    local character = player and player.Character
    if not character then return nil, nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return root, humanoid
end

local function hasFireTouch()
    return type(firetouchinterest) == "function"
end

-- Touch one coin from the client side (this is the legal replication path
-- every working hub uses).
local function touchCoin(root, coinPart)
    local ok = pcall(function()
        firetouchinterest(root, coinPart, 0)
        firetouchinterest(root, coinPart, 1)
    end)
    if ok then return true end
    -- Fallback: small dip onto the coin so the real touch fires.
    return pcall(function()
        local base = root.CFrame
        root.CFrame = CFrame.new(coinPart.Position + Vector3.new(0, 0.4, 0))
        task.wait(0.06)
        root.CFrame = base
    end)
end

local function nearestCoin(coins, root, maxDistance)
    local best, bestDist = nil, maxDistance or math.huge
    for _, coin in ipairs(coins) do
        if coin.Parent then
            local dist = (coin.Position - root.Position).Magnitude
            if dist < bestDist then
                best, bestDist = coin, dist
            end
        end
    end
    return best, bestDist
end

---------------------------------------------------------------------
-- Magnet loop: touch coins within radius, no movement.
---------------------------------------------------------------------

local function magnetTick()
    local root = getRoot()
    if not root then return end
    local coins = WorldRef.FindCoins(ConfigRef.Settings.FarmLobbyCoins)
    if #coins == 0 then return end
    local radius = ConfigRef.Settings.MagnetRadius or 24
    local touched = 0
    for _, coin in ipairs(coins) do
        if coin.Parent and (coin.Position - root.Position).Magnitude <= radius then
            if touchCoin(root, coin) then touched = touched + 1 end
            if ConfigRef.Settings.HumanizeDelays then task.wait(0.04 + math.random() * 0.05) end
            if touched >= 6 then break end -- per-tick cap, keep it calm
        end
    end
    if touched > 0 then
        Farm.CoinsCollected = Farm.CoinsCollected + touched
        Farm.Status = "магнит: " .. tostring(touched) .. " за такт"
    end
end

---------------------------------------------------------------------
-- Farm loop: travel to coins by the chosen mode.
---------------------------------------------------------------------

local function glideTo(root, humanoid, position, speed)
    local mode = ConfigRef.Settings.FarmMode or "Smooth"
    if mode == "Teleport" then
        if ConfigRef.Settings.SafeTeleport and StealthRef and StealthRef.GlideTo then
            local done = StealthRef.GlideTo(position, { Speed = speed or 60 })
            if done then task.wait(0.05) return true end
        end
        root.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
        task.wait(0.05)
        return true
    elseif mode == "Walk" and humanoid then
        humanoid:MoveTo(position)
        -- wait until close or timeout
        local started = os.clock()
        while (root.Position - position).Magnitude > 4 and os.clock() - started < 6 do
            if not root.Parent then return false end
            humanoid:MoveTo(position)
            task.wait(0.2)
        end
        return true
    else
        -- Smooth: frame-based lerp, reads like fast movement on the server.
        local distance = (position + Vector3.new(0, 2.5, 0) - root.Position).Magnitude
        local stepSpeed = speed or 60
        local timeout = distance / stepSpeed + 4
        local started = os.clock()
        while root.Parent do
            local target = position + Vector3.new(0, 2.5, 0)
            local offset = target - root.Position
            if offset.Magnitude < 3 then return true end
            if os.clock() - started > timeout then
                root.CFrame = CFrame.new(target)
                return true
            end
            local delta = RunService.Heartbeat:Wait() or 0.016
            local step = math.min(stepSpeed * delta, offset.Magnitude)
            root.CFrame = root.CFrame + offset.Unit * step
        end
        return false
    end
end

local function farmTick()
    local root, humanoid = getRoot()
    if not root then return end

    -- Bag full handling.
    if Farm.BagMax and Farm.BagCur and Farm.BagCur >= Farm.BagMax then
        if ConfigRef.Settings.LobbyOnFull and StealthRef and StealthRef.GlideTo then
            Farm.Status = "сумка полна — идём в лобби"
            local pos = WorldRef.GetLobbyPosition()
            StealthRef.GlideTo(pos, { Speed = ConfigRef.Settings.GlideSpeed or 48 })
            task.wait(2)
        elseif ConfigRef.Settings.StopOnFull then
            Farm.Status = "сумка полна (" .. tostring(Farm.BagCur) .. "/" .. tostring(Farm.BagMax) .. ") — пауза"
            task.wait(3)
            return
        end
    end

    local coins = WorldRef.FindCoins(ConfigRef.Settings.FarmLobbyCoins)
    if #coins == 0 then
        Farm.Status = WorldRef.GetMap() and "монет нет на карте" or "карта не найдена (лобби?)"
        return
    end

    local coin, dist = nearestCoin(coins, root, math.huge)
    if not coin then return end

    local moved = glideTo(root, humanoid, coin.Position, ConfigRef.Settings.FarmMode == "Teleport" and 70 or 55)
    if moved then
        local freshRoot = getRoot()
        if freshRoot then
            touchCoin(freshRoot, coin)
            Farm.CoinsCollected = Farm.CoinsCollected + 1
            Farm.Status = "фарм: " .. tostring(Farm.CoinsCollected) .. " (осталось " .. tostring(#coins - 1) .. ")"
        end
    end
end

---------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------

local function farmLoop()
    while running do
        if Farm.Enabled then
            local ok, err = pcall(farmTick)
            if not ok then
                Farm.Status = "ошибка: " .. tostring(err)
                note("farm: " .. tostring(err))
            end
        end
        local delay = math.max(0.35, ConfigRef.Settings.FarmDelay or 0.8)
        if ConfigRef.Settings.HumanizeDelays then delay = delay * (0.85 + math.random() * 0.4) end
        task.wait(delay)
    end
end

local function magnetLoop()
    while running do
        if Farm.MagnetEnabled then
            local ok, err = pcall(magnetTick)
            if not ok then note("magnet: " .. tostring(err)) end
        end
        local delay = 0.5
        if ConfigRef.Settings.HumanizeDelays then delay = delay * (0.8 + math.random() * 0.5) end
        task.wait(delay)
    end
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

function Farm.SetFarm(value)
    Farm.Enabled = value and true or false
    ConfigRef.Settings.CoinFarm = Farm.Enabled
    Farm.RefreshLoops()
end

function Farm.SetMagnet(value)
    Farm.MagnetEnabled = value and true or false
    ConfigRef.Settings.CoinMagnet = Farm.MagnetEnabled
    Farm.RefreshLoops()
end

function Farm.RefreshLoops()
    local want = (Farm.Enabled or Farm.MagnetEnabled)
    if want and not running then
        running = true
        loopThread = task.spawn(farmLoop)
        task.spawn(magnetLoop)
    elseif not want then
        running = false
        Farm.Status = "выключено"
    end
end

function Farm.Configure(config, world, stealth)
    ConfigRef = config
    WorldRef = world
    StealthRef = stealth
    Farm.Debug = config.Settings.DebugLogs == true

    pcall(function()
        -- ремоуты переезжают между апдейтами — ищем рекурсивно
        coinEvent = ReplicatedStorage:FindFirstChild("CoinCollected", true)
        if coinEvent then
            coinEvent.OnClientEvent:Connect(function(player, current, max)
                if current ~= nil then Farm.BagCur = tonumber(current) end
                if max ~= nil then Farm.BagMax = tonumber(max) end
            end)
        end
    end)
end

function Farm.Summary()
    local bag = "-"
    if Farm.BagCur then
        bag = tostring(Farm.BagCur) .. (Farm.BagMax and ("/" .. tostring(Farm.BagMax)) or "")
    end
    return string.format("собрано %d • сумка %s • %s", Farm.CoinsCollected, bag, Farm.Status or "")
end

function Farm.Destroy()
    running = false
end

return Farm
