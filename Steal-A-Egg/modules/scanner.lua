-- MilfaCheatHUB • dynamic game scanner
-- Reads replicated client state and Workspace without fixed egg coordinates.

local Scanner = {}
Scanner.__index = Scanner

local function safeRequire(instance)
    if not instance then return nil end
    local ok, value = pcall(require, instance)
    return ok and value or nil
end

local function findPath(root, path)
    local current = root
    for segment in string.gmatch(path, "[^%.]+") do
        current = current and current:FindFirstChild(segment)
    end
    return current
end

function Scanner.new(config)
    local self = setmetatable({}, Scanner)
    self.Config = config
    self.Players = game:GetService("Players")
    self.RS = game:GetService("ReplicatedStorage")
    self.Workspace = game:GetService("Workspace")
    self.Player = self.Players.LocalPlayer

    self.EggState = safeRequire(findPath(self.RS, "Client.EggState"))
    self.PlotState = safeRequire(findPath(self.RS, "Client.PlotState"))
    self.Save = safeRequire(findPath(self.RS, "Shared.Save"))

    local library = self.RS:FindFirstChild("Library")
    local clientLibrary = library and library:FindFirstChild("Client")
    self.EggCmds = self.EggState or safeRequire(clientLibrary and clientLibrary:FindFirstChild("EggCmds"))
    self.PlotCmds = self.PlotState or safeRequire(clientLibrary and clientLibrary:FindFirstChild("PlotCmds"))
    return self
end

function Scanner:GetSave()
    if not self.Save then
        self.Save = safeRequire(findPath(self.RS, "Shared.Save"))
    end
    local save = self.Save
    if type(save) == "table" then
        if type(save.Get) == "function" then
            local ok, value = pcall(save.Get)
            if ok and type(value) == "table" then return value end
        end
        return save
    end
    return nil
end

function Scanner:GetCharacter()
    return self.Player.Character
end

function Scanner:GetRoot()
    local character = self:GetCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

function Scanner:GetEggFolder()
    return self.Workspace:FindFirstChild("AreaEggSlotsClient")
        or self.Workspace:FindFirstChild("Eggs")
end

function Scanner:ReadEggSnapshot()
    if type(self.EggCmds) ~= "table" then return nil end
    for _, methodName in ipairs({"ReadFieldEggs", "GetAreaEggSnapshot", "RequestAreaEggSnapshot"}) do
        local method = self.EggCmds[methodName]
        if type(method) == "function" then
            local ok, result = pcall(method)
            if ok and type(result) == "table" then
                return result.Records or result
            end
        end
    end
    return nil
end

function Scanner:GetEggInstance(record)
    if record.Instance and record.Instance.Parent then return record.Instance end
    local folder = self:GetEggFolder()
    if not folder or not record.Uid then return nil end
    return folder:FindFirstChild(tostring(record.Uid))
end

function Scanner:GetEggPosition(record)
    local frame = record.BottomCFrame or record.CFrame
    if typeof(frame) == "CFrame" then return frame.Position end
    if typeof(record.Position) == "Vector3" then return record.Position end

    local instance = self:GetEggInstance(record)
    if not instance then return nil end
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Model") then return instance:GetPivot().Position end
    local part = instance:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

function Scanner:GetEggs()
    local records, seen = {}, {}
    local snapshot = self:ReadEggSnapshot()

    if type(snapshot) == "table" then
        for key, record in pairs(snapshot) do
            if type(record) == "table" then
                local uid = record.Uid or record.UID or record.Id
                if uid == nil and type(key) == "string" then uid = key end
                if uid then
                    record.Uid = uid
                    seen[tostring(uid)] = true
                    records[#records + 1] = record
                end
            end
        end
    end

    local folder = self:GetEggFolder()
    if folder then
        for _, instance in ipairs(folder:GetChildren()) do
            local uid = instance:GetAttribute("Uid") or instance:GetAttribute("Id") or instance.Name
            if not seen[tostring(uid)] then
                records[#records + 1] = {
                    Uid = uid,
                    AssetCategory = instance:GetAttribute("AssetCategory")
                        or instance:GetAttribute("EggName")
                        or instance.Name,
                    AreaId = instance:GetAttribute("Area") or instance:GetAttribute("AreaId"),
                    Instance = instance,
                    State = "ClientObject",
                }
                seen[tostring(uid)] = true
            end
        end
    end

    local root = self:GetRoot()
    table.sort(records, function(left, right)
        local leftPosition = self:GetEggPosition(left)
        local rightPosition = self:GetEggPosition(right)
        local leftDistance = root and leftPosition and (root.Position - leftPosition).Magnitude or math.huge
        local rightDistance = root and rightPosition and (root.Position - rightPosition).Magnitude or math.huge
        return leftDistance < rightDistance
    end)

    return records
end

function Scanner:GetPlot()
    if type(self.PlotCmds) == "table" then
        for _, methodName in ipairs({"ResolvePlot", "GetPlotData"}) do
            local method = self.PlotCmds[methodName]
            if type(method) == "function" then
                local ok, data = pcall(method)
                if ok and type(data) == "table" and (data.PetArea or data.CenterPoint) then
                    return data
                end
            end
        end
    end

    local plots = self.Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        local owner = plot:GetAttribute("Owner")
            or plot:GetAttribute("OwnerUserId")
            or plot:GetAttribute("OwnerId")
        if tostring(owner) == tostring(self.Player.UserId) or tostring(owner) == self.Player.Name then
            return {
                PlotFolder = plot,
                PetArea = plot:FindFirstChild("PetArea", true),
                CenterPoint = plot:FindFirstChild("CenterPoint", true),
            }
        end
    end
    return nil
end

function Scanner:GetAreas()
    local objects = self.Workspace:FindFirstChild("__OBJECTS")
    local areas = objects and objects:FindFirstChild("Areas")
    local guardAreas = areas and areas:FindFirstChild("GuardAreas")
    return guardAreas and guardAreas:GetChildren() or {}
end

function Scanner:Diagnostics()
    local eggs = self:GetEggs()
    local plot = self:GetPlot()
    local areas = self:GetAreas()
    return string.format(
        "Яйца: %d  •  Участок: %s  •  Биомы: %d",
        #eggs,
        plot and "найден" or "не найден",
        #areas
    )
end

return Scanner
