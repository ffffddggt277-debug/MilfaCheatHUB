-- MilfaCheatHUB • Murder Mystery 2
-- Role ESP v0.2.0 (added: tracers, alert beep, coin highlights).
--
-- Purely client-side visuals: Highlight (see-through-walls) + BillboardGui
-- (name, role label, distance) per player character, colored by role:
-- murderer red, sheriff blue, hero amber, innocent green.
-- Optional Beam-tracers from the local character to every drawn target.
-- GunDrop gets its own highlight + billboard; coins optionally highlighted.
-- All instances live directly on characters (no container scan risk);
-- names are random per refresh cycle (stealth doctrine).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local ESP = {}

ESP.Enabled = false
ESP.Debug = false
ESP.OnAlert = nil  -- callback(message) for GUI notifications

local ConfigRef = nil
local RolesRef = nil
local WorldRef = nil
local StealthRef = nil

local running = false
local loopThread = nil
local drawData = {}       -- [player] = {Highlight, Billboard, TextLabel, Beam, Attach0, Attach1}
local gunDropDraw = nil
local gunDropSeen = false
local lastAlertAt = 0
local coinDraws = {}      -- [coinPart] = Highlight
local beepSound = nil

local function note(...)
    if ESP.Debug then print("[mh esp]", ...) end
end

local function beep()
    pcall(function()
        if not beepSound then
            beepSound = Instance.new("Sound")
            beepSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
            beepSound.Volume = 0.6
            beepSound.Parent = SoundService
        end
        beepSound:Play()
    end)
end

local function cleanupDraw(data)
    if not data then return end
    -- NOTE: ipairs over {Highlight, Billboard} would stop at the first nil,
    -- leaking the other instance — check each explicitly.
    if data.Highlight then pcall(function() data.Highlight:Destroy() end) end
    if data.Billboard then pcall(function() data.Billboard:Destroy() end) end
    if data.Beam then pcall(function() data.Beam:Destroy() end) end
    if data.Attach0 then pcall(function() data.Attach0:Destroy() end) end
    if data.Attach1 then pcall(function() data.Attach1:Destroy() end) end
end

local function clearAll()
    for player, data in pairs(drawData) do
        cleanupDraw(data)
        drawData[player] = nil
    end
    if gunDropDraw then
        pcall(function() gunDropDraw.Highlight:Destroy() end)
        pcall(function() gunDropDraw.Billboard:Destroy() end)
        gunDropDraw = nil
    end
end

local function targetPart(character)
    return character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
end

local function distanceTo(position)
    local player = Players.LocalPlayer
    local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root or not position then return 0 end
    return (root.Position - position).Magnitude
end

local function buildBillboard(character, color)
    local head = targetPart(character)
    if not head then return nil end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = StealthRef and StealthRef.RandomName(12) or "rbxESP"
    billboard.Size = UDim2.new(0, 140, 0, 34)
    billboard.StudsOffset = Vector3.new(0, 2.6, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 400

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextStrokeTransparency = 0.35
    label.TextColor3 = color
    label.Text = ""
    label.Parent = billboard

    billboard.Parent = head
    return billboard, label
end

local function buildHighlight(character, color)
    local highlight = Instance.new("Highlight")
    highlight.Name = StealthRef and StealthRef.RandomName(10) or "rbxHL"
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.55
    highlight.OutlineTransparency = 0.1
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = character
    return highlight
end

local function drawPlayer(player, settings)
    local character = player.Character
    if not character or not character.Parent then return end
    local role = RolesRef.Get(player.Name) or "Unknown"
    local alive = RolesRef.IsAlive(player.Name)

    local isTarget = role == "Murderer" or role == "Sheriff" or role == "Hero"
    if settings.EspOnlyTargets and not isTarget then
        cleanupDraw(drawData[player])
        drawData[player] = nil
        return
    end
    if not alive then
        cleanupDraw(drawData[player])
        drawData[player] = nil
        return
    end

    local color = RolesRef.ColorFor(role)
    local data = drawData[player]

    if not data or not data.Highlight or not data.Highlight.Parent then
        cleanupDraw(data)
        data = { Highlight = nil, Billboard = nil, Label = nil }
        if settings.EspHighlight then
            data.Highlight = buildHighlight(character, color)
        end
        data.Billboard, data.Label = buildBillboard(character, color)
        drawData[player] = data
    else
        if data.Highlight then data.Highlight.FillColor = color; data.Highlight.OutlineColor = color end
        if data.Billboard then data.Billboard.AlwaysOnTop = true end
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local dist = rootPart and distanceTo(rootPart.Position) or 0
    if dist > (settings.EspMaxDistance or 1000) then
        cleanupDraw(data)
        drawData[player] = nil
        return
    end

    if data.Label then
        local parts = { player.Name }
        if settings.EspShowRole then parts[#parts + 1] = "[" .. RolesRef.Label(role) .. "]" end
        if settings.EspShowDistance then parts[#parts + 1] = string.format("%.0fм", dist) end
        data.Label.Text = table.concat(parts, " ")
        data.Label.TextColor3 = color
    end

    -- Murderer proximity alert (throttled to one per 6 seconds).
    if role == "Murderer" and settings.MurderAlert and dist <= (settings.MurderAlertDistance or 70) then
        local now = os.clock()
        if now - lastAlertAt > 6 then
            lastAlertAt = now
            if ESP.OnAlert then pcall(ESP.OnAlert, "МАНЬЯК рядом: " .. player.Name .. " (" .. string.format("%.0f", dist) .. "м)") end
            if settings.AlertBeep then beep() end
        end
    end

    -- Beam-трейсеры к целям (клиентский визуал).
    if settings.Tracers then
        local myRoot = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if myRoot and rootPart then
            if not data.Beam or not data.Beam.Parent then
                local ok = pcall(function()
                    local attach0 = Instance.new("Attachment")
                    attach0.Parent = myRoot
                    local attach1 = Instance.new("Attachment")
                    attach1.Parent = rootPart
                    local beam = Instance.new("Beam")
                    beam.Name = StealthRef and StealthRef.RandomName(10) or "rbxTrace"
                    beam.Attachment0 = attach0
                    beam.Attachment1 = attach1
                    beam.FaceCamera = true
                    beam.Width0 = 0.12
                    beam.Width1 = 0.12
                    beam.Transparency = NumberSequence.new(0.25)
                    beam.Color = ColorSequence.new(color)
                    beam.LightEmission = 0.8
                    beam.Parent = myRoot
                    data.Attach0 = attach0
                    data.Attach1 = attach1
                    data.Beam = beam
                end)
                if not ok then return end
            elseif data.Beam then
                data.Beam.Color = ColorSequence.new(color)
            end
        end
    elseif data.Beam then
        cleanupDraw(data)
        drawData[player] = nil
    end
end

local function drawGunDrop(settings)
    if not settings.GunDropESP and not settings.GunDropAlert then return end
    local drop = WorldRef.GetGunDrop()
    if not drop then
        gunDropSeen = false
        if gunDropDraw then
            pcall(function() gunDropDraw.Highlight:Destroy() end)
            pcall(function() gunDropDraw.Billboard:Destroy() end)
            gunDropDraw = nil
        end
        return
    end

    -- First sighting this cycle -> notification (if enabled).
    if not gunDropSeen then
        gunDropSeen = true
        if settings.GunDropAlert and ESP.OnAlert then
            local dist = distanceTo(drop.Position)
            pcall(ESP.OnAlert, "ПИСТОЛЕТ ВЫПАЛ! " .. string.format("%.0fм", dist) .. " — жми TP или включи автоподбор")
        end
    end

    if settings.GunDropESP then
        if not gunDropDraw or not gunDropDraw.Highlight or not gunDropDraw.Highlight.Parent then
            local color = Color3.fromRGB(64, 156, 255)
            local highlight = Instance.new("Highlight")
            highlight.Name = StealthRef and StealthRef.RandomName(10) or "rbxGD"
            highlight.FillColor = color
            highlight.OutlineColor = color
            highlight.FillTransparency = 0.35
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = drop

            local billboard = Instance.new("BillboardGui")
            billboard.Size = UDim2.new(0, 120, 0, 26)
            billboard.StudsOffset = Vector3.new(0, 2, 0)
            billboard.AlwaysOnTop = true
            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBold
            label.TextSize = 13
            label.TextStrokeTransparency = 0.35
            label.TextColor3 = color
            label.Text = "ПИСТОЛЕТ!"
            label.Parent = billboard
            billboard.Parent = drop

            gunDropDraw = { Highlight = highlight, Billboard = billboard }
        end
    end
end

local function clearCoins()
    for coin, highlight in pairs(coinDraws) do
        pcall(function() highlight:Destroy() end)
        coinDraws[coin] = nil
    end
end

local function drawCoins(settings)
    if not settings.CoinESP then
        if next(coinDraws) then clearCoins() end
        return
    end
    local coins = WorldRef.FindCoins(false)
    local alive = {}
    local limit = 60
    for index, coin in ipairs(coins) do
        if index > limit then break end
        alive[coin] = true
        if not coinDraws[coin] or not coinDraws[coin].Parent then
            pcall(function()
                local highlight = Instance.new("Highlight")
                highlight.Name = StealthRef and StealthRef.RandomName(9) or "rbxCoin"
                highlight.FillColor = Color3.fromRGB(255, 228, 92)
                highlight.OutlineColor = Color3.fromRGB(255, 228, 92)
                highlight.FillTransparency = 0.6
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.Parent = coin
                coinDraws[coin] = highlight
            end)
        end
    end
    for coin in pairs(coinDraws) do
        if not alive[coin] then
            pcall(function() coinDraws[coin]:Destroy() end)
            coinDraws[coin] = nil
        end
    end
end

local function loop()
    while running do
        local ok, err = pcall(function()
            local settings = ConfigRef.Settings
            pcall(function() RolesRef.Refresh() end)
            if settings.PlayerESP then
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= Players.LocalPlayer then
                        drawPlayer(player, settings)
                    end
                end
                -- drop stale entries
                for player in pairs(drawData) do
                    if not player.Parent or player == Players.LocalPlayer then
                        cleanupDraw(drawData[player])
                        drawData[player] = nil
                    end
                end
            else
                clearAll()
            end
            drawGunDrop(settings)
            drawCoins(settings)
        end)
        if not ok then note("loop: " .. tostring(err)) end
        local delay = math.max(0.4, ConfigRef.Settings.RefreshSeconds or 1)
        if ConfigRef.Settings.HumanizeDelays then delay = delay * (0.9 + math.random() * 0.3) end
        task.wait(delay)
    end
end

function ESP.SetCoins(value)
    ConfigRef.Settings.CoinESP = value and true or false
    if value and not running then
        running = true
        loopThread = task.spawn(loop)
    end
    if not value then clearCoins() end
end

function ESP.SetEnabled(value)
    ConfigRef.Settings.PlayerESP = value and true or false
    ESP.Enabled = value and true or false
    if value and not running then
        running = true
        loopThread = task.spawn(loop)
    elseif not value then
        running = false
        clearAll()
    end
end

function ESP.Configure(config, roles, world, stealth)
    ConfigRef = config
    RolesRef = roles
    WorldRef = world
    StealthRef = stealth
    ESP.Debug = config.Settings.DebugLogs == true
end

function ESP.Destroy()
    running = false
    clearAll()
    clearCoins()
end

return ESP
