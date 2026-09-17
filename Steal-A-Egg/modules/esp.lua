-- MilfaCheatHUB • client-side Egg ESP with rarity colors (stealth v0.4)

local ESP = {}
ESP.__index = ESP

local function randomName(stealth)
    if stealth and stealth.RandomName then return stealth.RandomName(14) end
    return "ESP_" .. tostring(math.random(100000, 999999))
end

local function safeParent(folder, stealth)
    -- Preferred: shared hidden container (CoreGui/gethui) — invisible to game scanners
    if stealth and stealth.GetContainer then
        local ok, container = pcall(stealth.GetContainer, stealth)
        if ok and container then
            local attached = pcall(function() folder.Parent = container end)
            if attached and folder.Parent == container then return true end
        end
    end

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

function ESP.new(config, rarity, stealth)
    local self = setmetatable({}, ESP)
    self.Config = config
    self.Rarity = rarity
    self.Stealth = stealth
    self.Enabled = false
    self.Objects = {}
    self.Folder = Instance.new("Folder")
    self.Folder.Name = randomName(stealth)
    safeParent(self.Folder, stealth)
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

    local settings = self.Config.Settings
    local colors = self.Config.Colors
    local root = scanner:GetRoot()
    local maxDistance = settings.EspMaxDistance or 1500

    for _, record in ipairs(records) do
        if not self.Enabled then break end
        local instance = scanner:GetEggInstance(record) or record.Instance
        local position = scanner:GetEggPosition(record) or record.Position
        local adornee = findAdornee(instance)

        if instance and adornee and position then
            local distance = root and math.floor((root.Position - position).Magnitude) or 0
            if distance <= maxDistance then
                local rarityId = record.Rarity or self.Rarity.FromRecord(record)
                local useRarityColor = settings.ShowRarity ~= false
                local fillColor = useRarityColor and self.Rarity.Color(rarityId) or colors.ESP
                local outlineColor = useRarityColor and self.Rarity.Color(rarityId) or colors.Accent

                local highlight = Instance.new("Highlight")
                highlight.Name = randomName(self.Stealth)
                highlight.Adornee = instance
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.FillColor = fillColor
                highlight.FillTransparency = 0.72
                highlight.OutlineColor = outlineColor
                highlight.OutlineTransparency = 0.05
                highlight.Parent = self.Folder
                self.Objects[#self.Objects + 1] = highlight

                local billboard = Instance.new("BillboardGui")
                billboard.Name = randomName(self.Stealth)
                billboard.Adornee = adornee
                billboard.Size = UDim2.fromOffset(210, 52)
                billboard.StudsOffset = Vector3.new(0, 3.4, 0)
                billboard.AlwaysOnTop = true
                billboard.MaxDistance = maxDistance
                billboard.Parent = self.Folder

                local name = record.Name or record.AssetCategory or record.DisplayName or record.Uid or "Egg"
                local area = record.AreaId and (" • " .. tostring(record.AreaId)) or ""
                local lines = tostring(name) .. area
                if settings.ShowRarity then
                    lines = lines .. "\n[" .. tostring(rarityId) .. "]"
                end
                if settings.ShowDistance then
                    lines = lines .. " " .. distance .. " studs"
                end

                local label = Instance.new("TextLabel")
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundTransparency = 1
                label.Text = lines
                label.RichText = false
                label.TextColor3 = useRarityColor and fillColor or colors.Text
                label.TextStrokeColor3 = colors.Background
                label.TextStrokeTransparency = 0.16
                label.Font = Enum.Font.Code
                label.TextSize = 12
                label.Parent = billboard
                self.Objects[#self.Objects + 1] = billboard
            end
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
