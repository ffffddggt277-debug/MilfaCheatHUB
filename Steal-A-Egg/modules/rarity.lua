-- MilfaCheatHUB • Steal An Egg
-- Rarity engine: detection, ranking and colors (wiki-confirmed tiers).

local Rarity = {}
Rarity.__index = Rarity

-- Detection order matters: first match wins (Uncommon before Common, etc.)
Rarity.List = {
    { Id = "Divine",    Rank = 100, Color = Color3.fromRGB(255, 228, 92),  Words = {"divine", "archangel", "world burner", "aetheron"} },
    { Id = "Eternal",   Rank = 95,  Color = Color3.fromRGB(41, 217, 255),  Words = {"eternal"} },
    { Id = "Secret",    Rank = 90,  Color = Color3.fromRGB(30, 26, 44),    Words = {"secret"} },
    { Id = "Cosmic",    Rank = 80,  Color = Color3.fromRGB(99, 102, 255),  Words = {"cosmic", "galaxy"} },
    { Id = "Godly",     Rank = 75,  Color = Color3.fromRGB(255, 92, 60),   Words = {"godly"} },
    { Id = "Brainrot",  Rank = 72,  Color = Color3.fromRGB(168, 85, 247),  Words = {"brainrot", "tung", "sahur", "bananita", "tralaledon", "patapim", "trulimero"} },
    { Id = "Monster",   Rank = 70,  Color = Color3.fromRGB(124, 200, 74),  Words = {"monster", "krakenoid", "dreadscale", "crocodon", "crawler", "froggo"} },
    { Id = "Mecha",     Rank = 68,  Color = Color3.fromRGB(152, 162, 178), Words = {"mecha", "robot"} },
    { Id = "Mythic",    Rank = 65,  Color = Color3.fromRGB(255, 61, 129),  Words = {"mythic", "mythical", "myth"} },
    { Id = "Giant",     Rank = 60,  Color = Color3.fromRGB(255, 128, 170), Words = {"giant", "colossal", "huge", " big "} },
    { Id = "Legendary", Rank = 50,  Color = Color3.fromRGB(255, 170, 40),  Words = {"legendary", "legend"} },
    { Id = "Epic",      Rank = 40,  Color = Color3.fromRGB(176, 90, 250),  Words = {"epic"} },
    { Id = "Rare",      Rank = 30,  Color = Color3.fromRGB(64, 140, 255),  Words = {"rare"} },
    { Id = "Uncommon",  Rank = 20,  Color = Color3.fromRGB(96, 202, 92),   Words = {"uncommon"} },
    { Id = "Common",    Rank = 10,  Color = Color3.fromRGB(178, 178, 178), Words = {"common"} },
    { Id = "Unknown",   Rank = 5,   Color = Color3.fromRGB(145, 138, 158), Words = {} },
}

local ById = {}
for _, entry in ipairs(Rarity.List) do
    ById[entry.Id] = entry
end

-- Fallback mapping for numeric rarity tiers (1..N)
Rarity.Tiers = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Godly", "Cosmic", "Secret", "Eternal", "Divine"}

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
        return Rarity.Detect(direct) or Rarity.Detect(tostring(record.AssetCategory or "")) or "Unknown"
    end
    if type(direct) == "number" then
        local index = math.floor(direct)
        return Rarity.Tiers[index] or "Unknown"
    end

    local candidates = {record.AssetCategory, record.EggName, record.DisplayName, record.Name, record.Category}
    for _, value in ipairs(candidates) do
        local detected = Rarity.Detect(tostring(value))
        if detected then return detected end
    end
    return "Unknown"
end

return Rarity
