-- MilfaCheatHUB • local player tweaks
-- Speed, jump, infinite jump, noclip, click TP, anti-AFK.

local Player = {}
Player.__index = Player

function Player.new(config)
    local self = setmetatable({}, Player)
    self.Config = config
    self.Players = game:GetService("Players")
    self.UserInput = game:GetService("UserInputService")
    self.RunService = game:GetService("RunService")
    self.VirtualUser = game:GetService("VirtualUser")
    self.Player = self.Players.LocalPlayer
    self.Connections = {}
    self.Original = {}
    return self
end

function Player:GetHumanoid()
    local character = self.Player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

function Player:ApplySpeed()
    local humanoid = self:GetHumanoid()
    if humanoid then
        humanoid.UseJumpPower = true
        humanoid.WalkSpeed = self.Config.Settings.WalkSpeed or 16
        humanoid.JumpPower = self.Config.Settings.JumpPower or 50
    end
end

function Player:ResetSpeed()
    self.Config.Settings.WalkSpeed = 16
    self.Config.Settings.JumpPower = 50
    self:ApplySpeed()
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

function Player:SetClickTP(value)
    self.Config.Settings.ClickTP = value == true
    if value and not self.Connections.ClickTP then
        self.Connections.ClickTP = self.UserInput.InputBegan:Connect(function(input, processed)
            if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if not self.Config.Settings.ClickTP then return end
            local mouse = self.Player:GetMouse()
            local target = mouse and mouse.Hit
            local root = self.Player.Character and self.Player.Character:FindFirstChild("HumanoidRootPart")
            if target and root then
                root.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
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
