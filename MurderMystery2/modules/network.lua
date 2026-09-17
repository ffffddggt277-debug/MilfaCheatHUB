-- MilfaCheatHUB • Murder Mystery 2
-- Remote registry v0.1.0 (lightweight).
--
-- MM2 networking map (verified from working hubs):
--   ReplicatedStorage.GetPlayerData                 (RemoteFunction, roles)
--   ReplicatedStorage.Remotes.Gameplay.*            (PlayerDataChanged, CoinCollected)
--   ReplicatedStorage.Remotes.Extras.GetTimer       (RemoteFunction, round timer)
--   Tool-local remotes live INSIDE the Knife/Gun tools (Stab, Events.*,
--   Gun.KnifeLocal.CreateBeam) — those are resolved at use time, not here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = {}

function Network.new(config)
    local self = setmetatable({}, { __index = Network })
    self.Config = config
    self.Found = {}
    return self
end

function Network:GetFolder()
    local ok, folder = pcall(function()
        return ReplicatedStorage:FindFirstChild("Remotes")
    end)
    return ok and folder or nil
end

-- Resolve a dotted path like "Remotes.Gameplay.CoinCollected" from ReplicatedStorage.
function Network:Resolve(path)
    if self.Found[path] and self.Found[path].Parent then
        return self.Found[path]
    end
    local current = ReplicatedStorage
    local ok = true
    for segment in string.gmatch(path, "[^.]+") do
        local found = nil
        pcall(function() found = current:FindFirstChild(segment) end)
        if not found then
            ok = false
            break
        end
        current = found
    end
    local result = ok and current or nil
    self.Found[path] = result
    return result
end

function Network:Summary()
    local checks = {
        { "GetPlayerData", "GetPlayerData", true },
        { "PlayerDataChanged", "Remotes.Gameplay.PlayerDataChanged", false },
        { "CoinCollected", "Remotes.Gameplay.CoinCollected", false },
        { "GetTimer", "Remotes.Extras.GetTimer", true },
    }
    local lines = {}
    for _, entry in ipairs(checks) do
        local instance = self:Resolve(entry[2])
        lines[#lines + 1] = entry[1] .. ": " .. (instance and "OK" or "нет")
    end
    return "Ремоуты — " .. table.concat(lines, " • ")
end

return Network
