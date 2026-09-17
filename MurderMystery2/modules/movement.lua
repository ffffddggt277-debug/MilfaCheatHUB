-- MilfaCheatHUB • Murder Mystery 2
-- Movement & teleports v0.1.0.
--
-- MM2 has no known movement anticheat (9 public hubs use WalkSpeed 18-50,
-- noclip via Humanoid:ChangeState(11), teleports freely). We still keep the
-- sane defaults: speed slider capped at 50, teleports through glide by
-- default (CALM doctrine), CharacterAdded re-apply.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Movement = {}

Movement.AntiAFKEnabled = false
Movement.Debug = false
Movement.OnNotify = nil

local ConfigRef = nil
local StealthRef = nil

local connections = {}
local noclipRunning = false
local infJumpRunning = false
local clickTPActive = false
local antiAFKConnection = nil
local clickTPConnection = nil
local localPlayer = Players.LocalPlayer

local function note(...)
    if Movement.Debug then print("[mh move]", ...) end
end

local function getCharacterParts()
    local character = localPlayer and localPlayer.Character
    if not character then return nil, nil end
    return character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------
-- Speed / jump
---------------------------------------------------------------------

function Movement.ApplySpeed(value)
    local humanoid = getCharacterParts()
    if humanoid and value and value > 0 then
        pcall(function() humanoid.WalkSpeed = value end)
    end
end

function Movement.ApplyJump(value)
    local humanoid = getCharacterParts()
    if humanoid and value and value > 0 then
        pcall(function()
            humanoid.UseJumpPower = true
            humanoid.JumpPower = value
        end)
    end
end

---------------------------------------------------------------------
-- Infinite jump
---------------------------------------------------------------------

local function setInfJump(value)
    infJumpRunning = value and true or false
    if value then
        task.spawn(function()
            while infJumpRunning do
                task.wait(0.05)
                if UserInputService.JumpRequest then
                    local humanoid = getCharacterParts()
                    if humanoid then pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end) end
                end
            end
        end)
    end
end

---------------------------------------------------------------------
-- Noclip
---------------------------------------------------------------------

local function setNoclip(value)
    noclipRunning = value and true or false
    if value then
        task.spawn(function()
            while noclipRunning do
                local _, root = getCharacterParts()
                if root then
                    pcall(function()
                        for _, part in ipairs(root.Parent:GetDescendants()) do
                            if part:IsA("BasePart") and part.CanCollide then
                                part.CanCollide = false
                            end
                        end
                    end)
                end
                RunService.Heartbeat:Wait()
            end
            -- restore collisions on disable
            local _, root = getCharacterParts()
            if root and root.Parent then
                pcall(function()
                    for _, part in ipairs(root.Parent:GetDescendants()) do
                        if part:IsA("BasePart") then part.CanCollide = true end
                    end
                    root.Parent.PrimaryPart = root
                    root.CanCollide = true
                end)
            end
        end)
    end
end

---------------------------------------------------------------------
-- Click TP (glide to clicked point)
---------------------------------------------------------------------

local function setClickTP(value)
    clickTPActive = value and true or false
    if value then
        if clickTPConnection then
            pcall(function() clickTPConnection:Disconnect() end)
            clickTPConnection = nil
        end
        clickTPConnection = UserInputService.InputBegan:Connect(function(input, processed)
            if not clickTPActive or processed then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            local camera = workspace.CurrentCamera
            if not camera then return end
            local ray = camera:ViewportPointToRay(input.Position.X, input.Position.Y)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local character = localPlayer and localPlayer.Character
            if character then params.FilterDescendantsInstances = { character } end
            local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
            if result and StealthRef and StealthRef.GlideTo then
                note("clickTP -> " .. tostring(result.Position))
                task.spawn(function()
                    StealthRef.GlideTo(result.Position + Vector3.new(0, 2, 0), {})
                end)
            end
        end)
    end
end

---------------------------------------------------------------------
-- Public toggles (used by features.lua)
---------------------------------------------------------------------

function Movement.SetInfJump(value)
    if ConfigRef then ConfigRef.Settings.InfiniteJump = value and true or false end
    setInfJump(value and true or false)
end

function Movement.SetNoclip(value)
    if ConfigRef then ConfigRef.Settings.Noclip = value and true or false end
    setNoclip(value and true or false)
end

function Movement.SetClickTP(value)
    if ConfigRef then ConfigRef.Settings.ClickTP = value and true or false end
    setClickTP(value and true or false)
end

---------------------------------------------------------------------
-- Teleports
---------------------------------------------------------------------

function Movement.ToLobby()
    if StealthRef and StealthRef.GlideTo then
        task.spawn(function()
            local position = Vector3.new(14.72, 506.2, -61.29)
            local world = Movement.WorldRef
            if world and world.GetLobbyPosition then
                local found = world.GetLobbyPosition()
                if found then position = found end
            end
            StealthRef.GlideTo(position, { Speed = ConfigRef.Settings.GlideSpeed or 48 })
            if Movement.OnNotify then pcall(Movement.OnNotify, "Телепорт в лобби выполнен") end
        end)
        return true
    end
    return false
end

function Movement.ToMap()
    -- WorldRef is injected to avoid a circular dependency.
    local world = Movement.WorldRef
    if not world then return false end
    local position = world.GetMapSpawn()
    if not position then return false end
    task.spawn(function()
        if StealthRef and StealthRef.GlideTo then
            StealthRef.GlideTo(position, { Speed = ConfigRef.Settings.GlideSpeed or 48 })
        else
            local _, root = getCharacterParts()
            if root then root.CFrame = CFrame.new(position) end
        end
        if Movement.OnNotify then pcall(Movement.OnNotify, "Телепорт на карту выполнен") end
    end)
    return true
end

function Movement.AboveMap()
    local world = Movement.WorldRef
    if not world then return false end
    local center = world.GetMapCenter()
    if not center then return false end
    local target = center + Vector3.new(0, 120, 0)
    task.spawn(function()
        local _, root = getCharacterParts()
        if not root then return end
        if StealthRef and StealthRef.GlideTo then
            StealthRef.GlideTo(target, { Speed = 90, Height = 0 })
        else
            root.CFrame = CFrame.new(target)
        end
        task.wait(0.4)
    end)
    return true
end

function Movement.ToPlayer(playerName)
    local target = nil
    for _, player in ipairs(Players:GetPlayers()) do
        if string.lower(player.Name) == string.lower(playerName or "") then target = player end
    end
    if not target or not target.Character then return false end
    local root = target.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    task.spawn(function()
        if StealthRef and StealthRef.GlideTo then
            StealthRef.GlideTo(root.Position, {})
        else
            local _, myRoot = getCharacterParts()
            if myRoot then myRoot.CFrame = root.CFrame * CFrame.new(0, 0, 3) end
        end
    end)
    return true
end

---------------------------------------------------------------------
-- Anti-AFK
---------------------------------------------------------------------

function Movement.SetAntiAFK(value)
    Movement.AntiAFKEnabled = value and true or false
    if value then
        local virtualUser = game:GetService("VirtualUser")
        antiAFKConnection = localPlayer.Idled:Connect(function()
            pcall(function()
                virtualUser:CaptureController()
                virtualUser:ClickButton2(Vector2.new())
            end)
            note("anti-afk pulse (idle)")
        end)
        connections[#connections + 1] = antiAFKConnection
        -- страховочный пульс каждые 60 секунд (не все экзекьюторы шлют Idled)
        task.spawn(function()
            while Movement.AntiAFKEnabled do
                task.wait(60)
                if not Movement.AntiAFKEnabled then break end
                pcall(function()
                    virtualUser:CaptureController()
                    virtualUser:ClickButton2(Vector2.new())
                end)
                note("anti-afk pulse (periodic)")
            end
        end)
    elseif antiAFKConnection then
        pcall(function() antiAFKConnection:Disconnect() end)
        antiAFKConnection = nil
    end
end

---------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------

function Movement.Configure(config, stealth)
    ConfigRef = config
    StealthRef = stealth
    Movement.Debug = config.Settings.DebugLogs == true

    -- Re-apply speed/jump on respawn.
    connections[#connections + 1] = localPlayer.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid", 5)
        if humanoid then
            task.wait(0.3)
            Movement.ApplySpeed(ConfigRef.Settings.WalkSpeed)
            Movement.ApplyJump(ConfigRef.Settings.JumpPower)
        end
    end)
    if localPlayer.Character then
        Movement.ApplySpeed(ConfigRef.Settings.WalkSpeed)
        Movement.ApplyJump(ConfigRef.Settings.JumpPower)
    end
end

function Movement.Destroy()
    noclipRunning = false
    infJumpRunning = false
    clickTPActive = false
    if clickTPConnection then
        pcall(function() clickTPConnection:Disconnect() end)
        clickTPConnection = nil
    end
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
    -- Full reset to vanilla values.
    local humanoid = getCharacterParts()
    if humanoid then
        pcall(function()
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end)
    end
end

return Movement
