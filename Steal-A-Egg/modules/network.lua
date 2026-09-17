-- MilfaCheatHUB • Networking diagnostics
-- This module discovers known remotes and reports their classes.

local Network = {}
Network.__index = Network

function Network.new(config)
    local self = setmetatable({}, Network)
    self.Config = config
    self.RS = game:GetService("ReplicatedStorage")
    self.CachedFolder = nil
    return self
end

function Network:GetFolder()
    if self.CachedFolder and self.CachedFolder.Parent then return self.CachedFolder end
    local packages = self.RS:FindFirstChild("Packages")
    self.CachedFolder = packages and packages:FindFirstChild("Networking")
    return self.CachedFolder
end

function Network:Find(endpoint)
    local folder = self:GetFolder()
    return folder and folder:FindFirstChild(endpoint) or nil
end

function Network:Scan()
    local rows = {}
    for _, endpoint in ipairs(self.Config.KnownEndpoints) do
        local instance = self:Find(endpoint)
        rows[#rows + 1] = {
            Endpoint = endpoint,
            Found = instance ~= nil,
            Class = instance and instance.ClassName or "missing",
            Instance = instance,
        }
    end
    return rows
end

function Network:Summary()
    local found, total = 0, 0
    for _, row in ipairs(self:Scan()) do
        total = total + 1
        if row.Found then found = found + 1 end
    end
    return string.format("Networking: %d/%d известных объектов найдено", found, total)
end

function Network:DetailedSummary(limit)
    local lines = {}
    for _, row in ipairs(self:Scan()) do
        if row.Found then
            lines[#lines + 1] = "✓ " .. row.Endpoint .. " [" .. row.Class .. "]"
        end
        if limit and #lines >= limit then break end
    end
    return #lines > 0 and table.concat(lines, "\n") or "Известные Remotes не найдены"
end

return Network
