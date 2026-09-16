-- MilfaCheatHUB • local player tweaks (stealth v0.4)
-- Speed without touching Humanoid.WalkSpeed (CFrame glide), jump, infinite jump,
-- noclip, glide click-TP, anti-AFK. BAC-safe by default.

local Player = {}
Player.__index = Player

function Player.new(config, stealth)
    local self = setmetatable({}, Player)
    self.Config = config
    self.Stealth = stealth
    self.Players = game:GetService("Players")
    self.UserInput = game:GetService("UserInputService")
    self.RunService = game:GetService("RunService")
    self.VirtualUser = game:GetService("VirtualUser")
    self.Player = self.Players.LocalPlayer
    self.Connections = {}
    self.Original = {}
    self:WatchRespawn()
    self:WatchStealthSpeed()
    return self
end

function Player:GetHumanoid()
    local character = self.Player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

-- Classic mode: sets WalkSpeed/JumpPower (visible to client anticheat watchers).
-- Stealth mode: does nothing — speed comes from CFrame glide below.
function Player:ApplySpeed()
    local settings = self.Config.Settings
    if settings.StealthSpeed then return end
    local humanoid = self:GetHumanoid()
    if humanoid then
        humanoid.UseJumpPower = true
        humanoid.WalkSpeed = settings.WalkSpeed or 16
        humanoid.JumpPower = settings.JumpPower or 50
    end
end

-- STEALTH SPEED: character glides via CFrame while the player holds movement.
-- Humanoid.WalkSpeed stays 16 so WalkSpeed-watchers never fire.
function Player:WatchStealthSpeed()
    if self.Connections.StealthSpeed then return end
    self.Connections.StealthSpeed = self.RunService.Heartbeat:Connect(function(deltaTime)
        local settings = self.Config.Settings
        if not settings.StealthSpeed then return end

        local character = self.Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not root or humanoid.Health <= 0 then return end

        local direction = humanoid.MoveDirection
        if direction.Magnitude < 0.05 then return end

        local speed = math.clamp(settings.StealthSpeedValue or 32, 16, 90)
        -- Humanized micro-jitter so movement is not perfectly linear.
        if settings.HumanizeDelays then
            speed = speed * (0.92 + math.random() * 0.16)
        end
        local step = direction * speed * deltaTime
        root.CFrame = root.CFrame + step
    end)
end

-- Re-apply speed/jump after respawn or character switch.
function Player:WatchRespawn()
    if self.Connections.Respawn then return end
    self.Connections.Respawn = self.Player.CharacterAdded:Connect(function()
        task.wait(0.6)
        pcall(function() self:ApplySpeed() end)
    end)
end

function Player:ResetSpeed()
    local settings = self.Config.Settings
    settings.WalkSpeed = 16
    settings.JumpPower = 50
    settings.StealthSpeed = false
    local humanoid = self:GetHumanoid()
    if humanoid then
        humanoid.UseJumpPower = true
        humanoid.WalkSpeed = 16
        humanoid.JumpPower = 50
    end
end

function Player:SetInfiniteJump(value)
    self.Config.Settings.InfiniteJump = value == true
    if value and not self.Connections.InfiniteJump then
        self.Connections.InfiniteJump = self.UserInput.JumpRequest:Connect(function()
            if not self.Config.Settings.InfiniteJump then return end
            local humanoid = self:GetHumanoid()
            if humanoid then
                pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
            end
        end)
    elseif not value and self.Connections.InfiniteJump then
        self.Connections.InfiniteJump:Disconnect()
        self.Connections.InfiniteJump = nil
    end
end

function Player:SetNoclip(value)
    self.Config.Settings.Noclip = value == true
    if value and not self.Connections.Noclip then
        self.Connections.Noclip = self.RunService.Stepped:Connect(function()
            if not self.Config.Settings.Noclip then return end
            local character = self.Player.Character
            if not character then return end
            for _, part in ipairs(character:GetChildren()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)
    elseif not value and self.Connections.Noclip then
        self.Connections.Noclip:Disconnect()
        self.Connections.Noclip = nil
        local character = self.Player.Character
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end
end

-- Click teleport now glides instead of a raw CFrame jump.
function Player:SetClickTP(value)
    self.Config.Settings.ClickTP = value == true
    if value and not self.Connections.ClickTP then
        self.Connections.ClickTP = self.UserInput.InputBegan:Connect(function(input, processed)
            if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if not self.Config.Settings.ClickTP then return end
            local mouse = self.Player:GetMouse()
            local target = mouse and mouse.Hit
            if target then
                if self.Stealth and self.Stealth.GlideTo then
                    self.Stealth.SafeTeleport = self.Config.Settings.SafeTeleport
                    self.Stealth.GlideSpeed = self.Config.Settings.GlideSpeed
                    task.spawn(function()
                        pcall(self.Stealth.GlideTo, self.Stealth, target.Position, {Height = 3})
                    end)
                else
                    local root = self.Player.Character and self.Player.Character:FindFirstChild("HumanoidRootPart")
                    if root then root.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0)) end
                end
            end
        end)
    elseif not value and self.Connections.ClickTP then
        self.Connections.ClickTP:Disconnect()
        self.Connections.ClickTP = nil
    end
end

function Player:SetAntiAFK(value)
    self.Config.Settings.AntiAFK = value == true
    if value and not self.Connections.AntiAFK then
        self.Connections.AntiAFK = self.Player.Idled:Connect(function()
            if not self.Config.Settings.AntiAFK then return end
            pcall(function()
                self.VirtualUser:CaptureController()
                self.VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    elseif not value and self.Connections.AntiAFK then
        self.Connections.AntiAFK:Disconnect()
        self.Connections.AntiAFK = nil
    end
end

function Player:Destroy()
    for _, connection in pairs(self.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    self.Connections = {}
    self.Config.Settings.InfiniteJump = false
    self.Config.Settings.Noclip = false
    self.Config.Settings.ClickTP = false
    self.Config.Settings.AntiAFK = false
    self:ResetSpeed()
end

return Player
