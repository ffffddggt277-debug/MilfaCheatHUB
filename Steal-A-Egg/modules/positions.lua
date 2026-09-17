-- MilfaCheatHUB • position resolver
-- Static values are diagnostics only; live objects are preferred.

local Positions = {}
Positions.__index = Positions

function Positions.new(config, scanner)
    local self = setmetatable({}, Positions)
    self.Config = config
    self.Scanner = scanner
    self.Static = {
        Anchor = Vector3.new(536.4492797851562, 70.28306579589844, -365.0294189453125),
        GateIn = Vector3.new(578, 70.3, -365.03),
        SafeZone = Vector3.new(545, 68, -364),
    }
    self.AreaX = {
        Forest = 602,
        Lake = 746,
        Desert = 785,
        Jungle = 936,
        Snow = 1076,
        Volcano = 1202,
        ["Abyss Ocean"] = 1370,
        Prehistoric = 1580,
        Cosmic = 1772,
        ["Cherry Blossom"] = 2479,
    }
    return self
end

local function instancePosition(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Model") then return instance:GetPivot().Position end
    local part = instance:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

function Positions:GetHome()
    local plot = self.Scanner:GetPlot()
    local petArea = plot and plot.PetArea
    local position = instancePosition(petArea)
    if position then return position, "Plot.PetArea" end

    local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    if spawn then return spawn.Position, spawn:GetFullName() end
    return nil, "missing"
end

function Positions:GetSeparationLine()
    local objects = workspace:FindFirstChild("__OBJECTS")
    local areas = objects and objects:FindFirstChild("Areas")
    local line = areas and areas:FindFirstChild("SeparationLine")
    return instancePosition(line), line
end

function Positions:GetDynamicPoints()
    local output = {}
    local home, source = self:GetHome()
    if home then output[#output + 1] = {Name = "Home", Position = home, Source = source} end

    local linePosition, line = self:GetSeparationLine()
    if linePosition then
        output[#output + 1] = {
            Name = "SeparationLine",
            Position = linePosition,
            Source = line:GetFullName(),
        }
    end

    for _, area in ipairs(self.Scanner:GetAreas()) do
        local position = instancePosition(area)
        if position then
            output[#output + 1] = {
                Name = area.Name,
                Position = position,
                Source = area:GetFullName(),
            }
        end
    end
    return output
end

function Positions:Summary()
    local points = self:GetDynamicPoints()
    local home = self:GetHome()
    return string.format(
        "Динамические точки: %d  •  База: %s",
        #points,
        home and "найдена" or "не найдена"
    )
end

function Positions:ListText(maxLines)
    local lines = {}
    for _, point in ipairs(self:GetDynamicPoints()) do
        local p = point.Position
        lines[#lines + 1] = string.format("%s: %.1f, %.1f, %.1f", point.Name, p.X, p.Y, p.Z)
        if maxLines and #lines >= maxLines then break end
    end
    return #lines > 0 and table.concat(lines, "\n") or "Динамические точки не найдены"
end

return Positions
