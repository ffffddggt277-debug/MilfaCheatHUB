-- MilfaCheatHUB • Murder Mystery 2
-- Role detection core v0.1.0.
--
-- Two channels (verified against live game structure, see FINDINGS_MM2.md):
--   1) Data: ReplicatedStorage.GetPlayerData (RemoteFunction) returns the whole
--      role table {[playerName] = {Role=..., Killed=..., Dead=...}}. The server
--      PUSHES updates through Remotes.Gameplay.PlayerDataChanged — that is how
--      the murderer is known BEFORE their knife is visible.
--   2) Tools fallback: Knife in Character/Backpack = Murderer, Gun = Sheriff;
--      an Innocent holding the gun = Hero (sheriff died, gun picked up).
-- The local player's role is latched per round (knife leaves the hand when
-- thrown, data may flicker — we keep the last known Murderer/Sheriff/Hero).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Roles = {}

Roles.Cache = {}          -- [playerName] = "Murderer" | "Sheriff" | "Hero" | "Innocent" | "Unknown"
Roles.Alive = {}          -- [playerName] = boolean (last known)
Roles.LocalRole = nil     -- latched own role for the round
Roles.Debug = false
Roles.OnUpdate = nil      -- callback(allRoles table) fired after each refresh

local dataRemote = nil
local pushEvent = nil
local connections = {}
local roundSeed = 0

local function note(...)
    if Roles.Debug then print("[mh roles]", ...) end
end

local function findRemotes()
    if dataRemote and dataRemote.Parent then return end
    -- Primary: ReplicatedStorage.GetPlayerData (RemoteFunction).
    local ok, result = pcall(function()
        return ReplicatedStorage:FindFirstChild("GetPlayerData")
    end)
    if ok and result and result:IsA("RemoteFunction") then
        dataRemote = result
    end
    -- Fallback: Remotes.Gameplay / *PlayerData*.
    if not dataRemote then
        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            local gameplay = remotes and remotes:FindFirstChild("Gameplay")
            if gameplay then
                for _, child in ipairs(gameplay:GetChildren()) do
                    local name = string.lower(child.Name)
                    if child:IsA("RemoteFunction") and string.find(name, "playerdata") then
                        dataRemote = child
                        break
                    end
                end
            end
        end)
    end
    -- Push channel: Remotes.Gameplay.PlayerDataChanged.
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local gameplay = remotes and remotes:FindFirstChild("Gameplay")
        if gameplay then
            pushEvent = gameplay:FindFirstChild("PlayerDataChanged") or pushEvent
        end
    end)
    note("remotes: data=" .. tostring(dataRemote ~= nil) .. " push=" .. tostring(pushEvent ~= nil))
end

local function normalizeRole(value)
    if type(value) ~= "string" or value == "" then return "Unknown" end
    local lowered = string.lower(value)
    if string.find(lowered, "murder", 1, true) then return "Murderer" end
    if string.find(lowered, "sheriff", 1, true) then return "Sheriff" end
    if string.find(lowered, "hero", 1, true) then return "Hero" end
    if string.find(lowered, "inno", 1, true) then return "Innocent" end
    return value
end

local function markRoundReset()
    roundSeed = roundSeed + 1
    Roles.LocalRole = nil
end

-- TOOL-FALLBACK: knife/gun scan. Innocent holding the gun becomes Hero.
local function detectFromTools()
    local found = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local held = nil
        pcall(function()
            local backpack = player:FindFirstChildOfClass("Backpack")
            local character = player.Character
            if backpack and (backpack:FindFirstChild("Knife") or (character and character:FindFirstChild("Knife"))) then
                held = "Murderer"
            elseif backpack and (backpack:FindFirstChild("Gun") or (character and character:FindFirstChild("Gun"))) then
                held = "Sheriff"
            end
        end)
        if held then
            local current = Roles.Cache[player.Name]
            if current == "Innocent" or current == nil or current == "Unknown" then
                found[player.Name] = held
            end
        end
    end
    return found
end

-- Pull the whole role table from the RemoteFunction. The payload is either
-- {[name] = {Role=...}} or a single record {[name] = Role-string}.
local function pullFromData()
    if not dataRemote then return nil end
    local ok, payload = pcall(function() return dataRemote:InvokeServer() end)
    if not ok or type(payload) ~= "table" then
        note("pull failed: " .. tostring(payload))
        return nil
    end
    return payload
end

function Roles.Refresh()
    findRemotes()
    -- Re-arm the push listener if a previous session shut it down.
    Roles.Listen()

    local data = pullFromData()
    if data then
        for name, record in pairs(data) do
            if type(name) == "string" then
                local role = "Unknown"
                local alive = true
                if type(record) == "table" then
                    role = normalizeRole(record.Role)
                    alive = not record.Killed and not record.Dead
                elseif type(record) == "string" then
                    role = normalizeRole(record)
                end
                Roles.Cache[name] = role
                Roles.Alive[name] = alive
                if Players.LocalPlayer and name == Players.LocalPlayer.Name and role ~= "Unknown" then
                    Roles.LocalRole = role
                end
            end
        end
    end

    -- Tools may reveal roles the data pull missed (e.g. RF absent in a build).
    for name, role in pairs(detectFromTools()) do
        Roles.Cache[name] = role
        Roles.Alive[name] = Roles.Alive[name] ~= false
    end

    if Roles.OnUpdate then pcall(Roles.OnUpdate, Roles.Cache) end
end

function Roles.Get(playerName)
    return Roles.Cache[playerName or ""]
end

function Roles.IsAlive(playerName)
    local value = Roles.Alive[playerName or ""]
    if value == nil then return true end
    return value and true or false
end

function Roles.ColorFor(role)
    local colors = {
        Murderer = Color3.fromRGB(255, 64, 64),
        Sheriff = Color3.fromRGB(64, 156, 255),
        Hero = Color3.fromRGB(255, 196, 47),
        Innocent = Color3.fromRGB(82, 255, 143),
    }
    return colors[role] or Color3.fromRGB(160, 160, 170)
end

function Roles.Label(role)
    local labels = {
        Murderer = "МАНЬЯК",
        Sheriff = "ШЕРИФ",
        Hero = "ГЕРОЙ",
        Innocent = "мирный",
        Unknown = "???",
    }
    return labels[role] or tostring(role)
end

function Roles.CountAliveByRole(role)
    local count = 0
    for name, cached in pairs(Roles.Cache) do
        if cached == role and Roles.IsAlive(name) then count = count + 1 end
    end
    return count
end

function Roles.FindByRole(role)
    local list = {}
    for name, cached in pairs(Roles.Cache) do
        if cached == role and Roles.IsAlive(name) then list[#list + 1] = name end
    end
    return list
end

function Roles.LocalIsMurderer()
    return Roles.LocalRole == "Murderer"
end

function Roles.LocalIsSheriff()
    return Roles.LocalRole == "Sheriff" or Roles.LocalRole == "Hero"
end

-- Round boundary: any role table reset (new round) clears the latch.
Roles.ResetRound = markRoundReset

function Roles.Listen()
    if pushEvent and not Roles._pushConnected then
        Roles._pushConnected = true
        local connection = pushEvent.OnClientEvent:Connect(function(payload)
            if type(payload) ~= "table" then return end
            -- Full table push resets roles that vanished (round change).
            local seen = {}
            for name, record in pairs(payload) do
                if type(name) == "string" then
                    seen[name] = true
                    local role, alive = "Unknown", true
                    if type(record) == "table" then
                        role = normalizeRole(record.Role)
                        alive = not record.Killed and not record.Dead
                    elseif type(record) == "string" then
                        role = normalizeRole(record)
                    end
                    Roles.Cache[name] = role
                    Roles.Alive[name] = alive
                    if Players.LocalPlayer and name == Players.LocalPlayer.Name and role ~= "Unknown" then
                        if Roles.LocalRole ~= "Murderer" or role ~= "Innocent" then
                            Roles.LocalRole = role
                        end
                    end
                end
            end
            for name in pairs(Roles.Cache) do
                if not seen[name] then
                    Roles.Cache[name] = nil
                    Roles.Alive[name] = nil
                    markRoundReset()
                end
            end
            if Roles.OnUpdate then pcall(Roles.OnUpdate, Roles.Cache) end
        end)
        connections[#connections + 1] = connection
    end
end

function Roles.Shutdown()
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    connections = {}
    Roles._pushConnected = false
end

Roles.Listen()

return Roles
