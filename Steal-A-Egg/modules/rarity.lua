-- MilfaCheatHUB • Steal An Egg
-- Rarity engine: detection, ranking and colors (wiki + community tiers).

local Rarity = {}
Rarity.__index = Rarity

-- Detection order matters: first match wins (Uncommon before Common, etc.)
Rarity.List = {
    { Id = "Divine",    Rank = 100, Color = Color3.fromRGB(255, 228, 92),  Words = {"divine", "transcendent", "superior", "archangel", "world burner", "aetheron"} },
    { Id = "Eternal",   Rank = 95,  Color = Color3.fromRGB(41, 217, 255),  Words = {"eternal", "limited"} },
    { Id = "Secret",    Rank = 90,  Color = Color3.fromRGB(30, 26, 44),    Words = {"secret", "exotic"} },
    { Id = "Cosmic",    Rank = 80,  Color = Color3.fromRGB(99, 102, 255),  Words = {"cosmic", "galaxy", "exclusive", "admin"} },
    { Id = "Titan",     Rank = 78,  Color = Color3.fromRGB(255, 110, 64),  Words = {"titan", "colossal", "giant", "huge"} },
    { Id = "LightDark", Rank = 77,  Color = Color3.fromRGB(120, 160, 255), Words = {"light & dark", "lightdark", "light and dark"} },
    { Id = "Godly",     Rank = 75,  Color = Color3.fromRGB(255, 92, 60),   Words = {"godly"} },
    { Id = "Brainrot",  Rank = 72,  Color = Color3.fromRGB(168, 85, 247),  Words = {"brainrot", "tung", "sahur", "bananita", "tralaledon", "patapim", "trulimero"} },
    { Id = "Monster",   Rank = 70,  Color = Color3.fromRGB(124, 200, 74),  Words = {"monster", "krakenoid", "dreadscale", "crocodon", "crawler", "froggo"} },
    { Id = "Mecha",     Rank = 68,  Color = Color3.fromRGB(152, 162, 178), Words = {"mecha", "robot"} },
    { Id = "Mythic",    Rank = 65,  Color = Color3.fromRGB(255, 61, 129),  Words = {"mythic", "mythical", "myth", "prismatic", "rainbow", "brainrot god"} },
    { Id = "Legendary", Rank = 50,  Color = Color3.fromRGB(255, 170, 40),  Words = {"legendary", "legend"} },
    { Id = "Epic",      Rank = 40,  Color = Color3.fromRGB(176, 90, 250),  Words = {"epic"} },
    { Id = "Rare",      Rank = 30,  Color = Color3.fromRGB(64, 140, 255),  Words = {"rare", "superrare", "super rare", "celestial"} },
    { Id = "Uncommon",  Rank = 20,  Color = Color3.fromRGB(96, 202, 92),   Words = {"uncommon"} },
    { Id = "Common",    Rank = 10,  Color = Color3.fromRGB(178, 178, 178), Words = {"common", "basic"} },
    { Id = "Unknown",   Rank = 5,   Color = Color3.fromRGB(145, 138, 158), Words = {} },
}

local ById = {}
for _, entry in ipairs(Rarity.List) do
    ById[entry.Id] = entry
end

-- Fallback mapping for numeric rarity tiers (1..N)
Rarity.Tiers = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Godly", "Cosmic", "Secret", "Eternal", "Divine"}
Rarity._CategoryCache = {}

-- Lazy catalog of the game: RS.Data.Assets.Directory[category].Rarity
local Catalog = nil
local function loadCatalog()
    if Catalog ~= nil then return Catalog end
    local RS = game:GetService("ReplicatedStorage")
    local candidates = {}
    local data = RS:FindFirstChild("Data")
    if data then
        candidates[#candidates + 1] = data:FindFirstChild("Assets")
        candidates[#candidates + 1] = data
    end
    local shared = RS:FindFirstChild("Shared")
    if shared then
        candidates[#candidates + 1] = shared:FindFirstChild("Assets")
        local util = shared:FindFirstChild("Util")
        if util then candidates[#candidates + 1] = util:FindFirstChild("Assets") end
    end
    for _, instance in ipairs(candidates) do
        if instance and instance:IsA("ModuleScript") then
            local ok, module = pcall(require, instance)
            if ok and type(module) == "table" then
                if type(module.Directory) == "table" then
                    Catalog = module.Directory
                    return Catalog
                end
                local count = 0
                for key, value in pairs(module) do
                    if type(value) == "table" then count = count + 1 end
                end
                if count > 5 then
                    Catalog = module
                    return Catalog
                end
            end
        end
    end
    Catalog = false
    return Catalog
end

-- Resolve a rarity for an asset category via the in-game catalog (cached).
function Rarity.FromCategory(category)
    if type(category) ~= "string" or category == "" then return nil end
    local cache = Rarity._CategoryCache
    local cached = cache[category]
    if cached ~= nil then
        return cached or nil
    end
    local result = nil
    local directory = loadCatalog()
    if directory then
        local entry = directory[category]
        if type(entry) == "table" then
            local rarity = entry.Rarity
            if type(rarity) == "table" then
                result = Rarity.Detect(tostring(rarity._id or rarity.DisplayName or rarity.Name or ""))
            elseif type(rarity) == "string" then
                result = Rarity.Detect(rarity)
            elseif type(rarity) == "number" then
                result = Rarity.Tiers[math.floor(rarity)]
            end
            if not result then
                result = Rarity.Detect(tostring(entry.DisplayName or entry.Name or ""))
            end
        end
    end
    cache[category] = result or false
    return result
end

-- Resolve a rarity straight from an egg/pet instance (attributes or Data values).
function Rarity.FromInstance(instance)
    if not instance or not instance.Parent then return nil end
    local ok, attr = pcall(function()
        return instance:GetAttribute("Rarity")
            or instance:GetAttribute("RarityName")
            or instance:GetAttribute("RarityTier")
    end)
    if ok and type(attr) == "string" and attr ~= "" then
        return Rarity.Detect(attr)
    end
    if ok and type(attr) == "number" then
        return Rarity.Tiers[math.floor(attr)]
    end
    local data = instance:FindFirstChild("Data")
    if data then
        local rarityValue = data:FindFirstChild("Rarity")
        if rarityValue and rarityValue:IsA("ValueBase") then
            local valueOk, value = pcall(function() return rarityValue.Value end)
            if valueOk then
                if type(value) == "string" then return Rarity.Detect(value) end
                if type(value) == "number" then return Rarity.Tiers[math.floor(value)] end
            end
        end
    end
    return nil
end

function Rarity.ById(id)
    return ById[tostring(id)] or ById.Unknown
end

function Rarity.Rank(id)
    return Rarity.ById(id).Rank
end

function Rarity.Color(id)
    return Rarity.ById(id).Color
end

function Rarity.Ids()
    local out = {}
    for _, entry in ipairs(Rarity.List) do
        out[#out + 1] = entry.Id
    end
    return out
end

function Rarity.ValueIds()
    -- High-tier ids used by "keep" defaults (everything above Rare)
    return {"Legendary", "Mythic", "Giant", "Godly", "Brainrot", "Monster", "Mecha", "Cosmic", "Secret", "Eternal", "Divine"}
end

function Rarity.Detect(text)
    if type(text) ~= "string" or text == "" then return nil end
    local lowered = " " .. string.lower(text) .. " "
    for _, entry in ipairs(Rarity.List) do
        for _, word in ipairs(entry.Words) do
            if string.find(lowered, word, 1, true) then
                return entry.Id
            end
        end
    end
    return nil
end

function Rarity.FromRecord(record)
    if type(record) ~= "table" then return "Unknown" end

    local direct = record.Rarity or record.RarityTier or record.RarityName
    if type(direct) == "string" and direct ~= "" then
        return Rarity.Detect(direct)
            or Rarity.FromCategory(tostring(record.AssetCategory or ""))
            or Rarity.Detect(tostring(record.AssetCategory or ""))
            or "Unknown"
    end
    if type(direct) == "number" then
        local index = math.floor(direct)
        return Rarity.Tiers[index] or "Unknown"
    end

    local fromCategory = Rarity.FromCategory(tostring(record.AssetCategory or record.Category or ""))
    if fromCategory then return fromCategory end

    local candidates = {record.AssetCategory, record.EggName, record.DisplayName, record.Name, record.Category}
    for _, value in ipairs(candidates) do
        local detected = Rarity.Detect(tostring(value))
        if detected then return detected end
    end
    return "Unknown"
end

return Rarity
