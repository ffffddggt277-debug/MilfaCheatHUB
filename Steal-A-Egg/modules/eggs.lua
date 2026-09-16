-- MilfaCheatHUB • egg engine
-- Rich egg records: rarity, prompts, distance, filters and sell remote discovery.

local Eggs = {}
Eggs.__index = Eggs

function Eggs.new(config, scanner, network, rarity)
    local self = setmetatable({}, Eggs)
    self.Config = config
    self.Scanner = scanner
    self.Network = network
    self.Rarity = rarity
    self.Workspace = game:GetService("Workspace")
    self.Players = game:GetService("Players")
    self.Player = self.Players.LocalPlayer
    return self
end

function Eggs:GetRoot()
    local character = self.Player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function partOf(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then return instance end
    return instance:FindFirstChild("Hitbox")
        or instance.PrimaryPart
        or instance:FindFirstChildWhichIsA("BasePart", true)
end

function Eggs:GetEggFolders()
    local folders = {}
    for _, name in ipairs({"AreaEggSlotsClient", "Eggs", "SpawnedEggs"}) do
        local folder = self.Workspace:FindFirstChild(name)
        if folder then folders[#folders + 1] = folder end
    end
    return folders
end

-- Collect every visible egg on the map with rich metadata.
function Eggs:Scan()
    local records, seen = {}, {}
    local root = self:GetRoot()

    -- 1) Server snapshot through client state (best data)
    local snapshot = self.Scanner:ReadEggSnapshot()
    if type(snapshot) == "table" then
        for key, record in pairs(snapshot) do
            if type(record) == "table" then
                local uid = record.Uid or record.UID or record.Id or (type(key) == "string" and key)
                if uid and not seen[tostring(uid)] then
                    seen[tostring(uid)] = true
                    records[#records + 1] = {
                        Uid = tostring(uid),
                        Name = tostring(record.AssetCategory or record.EggName or record.DisplayName or uid),
                        Instance = self.Scanner:GetEggInstance(record),
                        State = record.State or "Snapshot",
                    }
                end
            end
        end
    end

    -- 2) Workspace folders
    for _, folder in ipairs(self:GetEggFolders()) do
        for _, instance in ipairs(folder:GetChildren()) do
            local lowered = string.lower(instance.Name)
            if not string.find(lowered, "nest", 1, true) and not seen[tostring(instance.Name)] then
                seen[tostring(instance.Name)] = true
                records[#records + 1] = {
                    Uid = tostring(instance:GetAttribute("UID") or instance:GetAttribute("Uid") or instance.Name),
                    Name = instance.Name,
                    Instance = instance,
                    State = "ClientObject",
                }
            end
        end
    end

    -- 3) Native steal prompts (SmartPromptPart)
    for _, instance in ipairs(self.Workspace:GetChildren()) do
        if instance.Name == "SmartPromptPart" then
            local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt")
            if prompt then
                local key = "prompt_" .. tostring(instance.Position)
                if not seen[key] then
                    seen[key] = true
                    records[#records + 1] = {
                        Uid = key,
                        Name = tostring(prompt.ObjectText ~= "" and prompt.ObjectText or "Egg"),
                        Instance = instance,
                        Prompt = prompt,
                        State = "Prompt",
                    }
                end
            end
        end
    end

    -- Enrich records
    for _, record in ipairs(records) do
        record.Rarity = self.Rarity.FromRecord(record)
        record.Rank = self.Rarity.Rank(record.Rarity)
        local part = partOf(record.Instance)
        record.Part = part
        record.Position = part and part.Position or nil
        record.Distance = (root and record.Position) and math.floor((root.Position - record.Position).Magnitude) or math.huge
        record.Prompt = record.Prompt or (record.Instance and record.Instance:FindFirstChildWhichIsA("ProximityPrompt", true))
    end

    return records
end

function Eggs:Filter(records, options)
    options = options or {}
    local filterList = options.Rarities
    local maxDistance = options.MaxDistance or 0
    local query = options.Query and string.lower(options.Query) or nil

    local allowed = nil
    if type(filterList) == "table" and #filterList > 0 then
        allowed = {}
        for _, id in ipairs(filterList) do allowed[tostring(id)] = true end
    end

    local out = {}
    for _, record in ipairs(records) do
        local ok = true
        if allowed and not allowed[record.Rarity] then ok = false end
        if ok and maxDistance > 0 and record.Distance > maxDistance then ok = false end
        if ok and query and query ~= "" then
            local nameLower = string.lower(record.Name)
            if not string.find(nameLower, query, 1, true) then ok = false end
        end
        if ok then out[#out + 1] = record end
    end
    return out
end

function Eggs:Sort(records, mode)
    local root = self:GetRoot()
    table.sort(records, function(left, right)
        if mode == "distance" then
            return left.Distance < right.Distance
        end
        if left.Rank ~= right.Rank then return left.Rank > right.Rank end
        return left.Distance < right.Distance
    end)
    return records
end

-- Held egg: Tool/Model with "egg" in the name inside character or backpack.
function Eggs:GetHeldEgg()
    local character = self.Player.Character
    local containers = {character, self.Player:FindFirstChild("Backpack")}
    for _, container in ipairs(containers) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if (item:IsA("Tool") or item:IsA("Model")) and string.find(string.lower(item.Name), "egg", 1, true) then
                    return item
                end
            end
        end
    end
    return nil
end

function Eggs:GetHeldEggUid()
    local held = self:GetHeldEgg()
    if not held then return nil, nil end
    return held:GetAttribute("UID") or held:GetAttribute("Uid") or held.Name, held
end

-- Dynamic sell remote discovery inside Packages.Networking (+ static fallbacks).
function Eggs:FindSellRemotes()
    local found = {}
    local seen = {}
    local folder = self.Network:GetFolder()
    if folder then
        for _, instance in ipairs(folder:GetDescendants()) do
            if instance:IsA("RemoteFunction") or instance:IsA("RemoteEvent") then
                local lowered = string.lower(instance.Name)
                if string.find(lowered, "sell", 1, true) or string.find(lowered, "sale", 1, true) then
                    if not seen[instance:GetFullName()] then
                        seen[instance:GetFullName()] = true
                        found[#found + 1] = instance
                    end
                end
            end
        end
    end
    for _, name in ipairs(self.Config.SellCandidates or {}) do
        local instance = self.Network:Find(name)
        if instance and not seen[instance:GetFullName()] then
            seen[instance:GetFullName()] = true
            found[#found + 1] = instance
        end
    end
    return found
end

-- Pets roster via client modules (best effort) for rarity-filtered selling.
function Eggs:GetPetRoster()
    local RS = game:GetService("ReplicatedStorage")
    local modules = {RS:FindFirstChild("Client"), RS:FindFirstChild("Library")}
    for _, root in ipairs(modules) do
        if root then
            for _, name in ipairs({"PenRosterCmds", "PetCmds", "RosterCmds"}) do
                local folder = root:FindFirstChild(name) or (root:FindFirstChild("Client") and root.Client:FindFirstChild(name))
                if folder then
                    local ok, module = pcall(require, folder)
                    if ok and type(module) == "table" then
                        for _, method in ipairs({"GetRoster", "GetPets", "ReadRoster", "GetPenRoster", "GetRosterData"}) do
                            local fn = module[method]
                            if type(fn) == "function" then
                                local callOk, data = pcall(fn)
                                if callOk and type(data) == "table" then
                                    return data, name .. "." .. method
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, "not found"
end

return Eggs
