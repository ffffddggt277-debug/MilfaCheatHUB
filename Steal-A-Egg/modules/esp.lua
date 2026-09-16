-- MilfaCheatHUB • client-side Egg ESP

local ESP = {}
ESP.__index = ESP

local function safeParent(folder)
    local targets = {}
    if gethui then
        local ok, value = pcall(gethui)
        if ok and value then targets[#targets + 1] = value end
    end
    targets[#targets + 1] = game:GetService("CoreGui")
    local player = game:GetService("Players").LocalPlayer
    if player then targets[#targets + 1] = player:FindFirstChildOfClass("PlayerGui") end

    for _, target in ipairs(targets) do
        if target then
            local ok = pcall(function() folder.Parent = target end)
            if ok and folder.Parent then return true end
        end
    end
    return false
end

function ESP.new(config)
    local self = setmetatable({}, ESP)
    self.Config = config
    self.Enabled = false
    self.Objects = {}
    self.Folder = Instance.new("Folder")
    self.Folder.Name = "MilfaCheatHUB_ESP"
    safeParent(self.Folder)
    return self
end

function ESP:Clear()
    for _, object in ipairs(self.Objects) do
        pcall(function() object:Destroy() end)
    end
    self.Objects = {}
end

function ESP:SetEnabled(value)
    self.Enabled = value == true
    if not self.Enabled then self:Clear() end
end

local function findAdornee(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then return instance end
    return instance:FindFirstChildWhichIsA("BasePart", true)
end

function ESP:Refresh(records, scanner)
    if not self.Enabled or not self.Folder or not self.Folder.Parent then return end
    self:Clear()

    local root = scanner:GetRoot()
    for _, record in ipairs(records) do
        if not self.Enabled then break end
        local instance = scanner:GetEggInstance(record)
        local position = scanner:GetEggPosition(record)
        local adornee = findAdornee(instance)

        if instance and adornee and position then
            local highlight = Instance.new("Highlight")
            highlight.Name = "MilfaEggHighlight"
            highlight.Adornee = instance
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor = self.Config.Colors.ESP
            highlight.FillTransparency = 0.72
            highlight.OutlineColor = self.Config.Colors.Accent
            highlight.OutlineTransparency = 0.05
            highlight.Parent = self.Folder
            self.Objects[#self.Objects + 1] = highlight

            local billboard = Instance.new("BillboardGui")
            billboard.Name = "MilfaEggLabel"
            billboard.Adornee = adornee
            billboard.Size = UDim2.fromOffset(210, 42)
            billboard.StudsOffset = Vector3.new(0, 3.4, 0)
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 1500
            billboard.Parent = self.Folder

            local distance = root and math.floor((root.Position - position).Magnitude) or 0
            local name = record.AssetCategory or record.DisplayName or record.Uid or "Egg"
            local area = record.AreaId and (" • " .. tostring(record.AreaId)) or ""

            local label = Instance.new("TextLabel")
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.Text = tostring(name) .. area
                .. (self.Config.Settings.ShowDistance and ("\n" .. distance .. " studs") or "")
            label.TextColor3 = self.Config.Colors.Text
            label.TextStrokeColor3 = self.Config.Colors.Background
            label.TextStrokeTransparency = 0.16
            label.Font = Enum.Font.Code
            label.TextSize = 12
            label.Parent = billboard
            self.Objects[#self.Objects + 1] = billboard
        end
    end
end

function ESP:Destroy()
    self.Enabled = false
    self:Clear()
    if self.Folder then
        self.Folder:Destroy()
        self.Folder = nil
    end
end

return ESP
