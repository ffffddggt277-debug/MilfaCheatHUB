-- MilfaCheatHUB • automation engine
-- Auto steal / place / hatch / sell / collect / treadmill / server hop.

local Automation = {}
Automation.__index = Automation

function Automation.new(config, eggs, network, positions, scanner, rarity)
    local self = setmetatable({}, Automation)
    self.Config = config
    self.Eggs = eggs
    self.Network = network
    self.Positions = positions
    self.Scanner = scanner
    self.Rarity = rarity
    self.Running = false
    self.EmptyRuns = 0
    self.LastHop = 0
    self.Status = {
        Steal = "выключено",
        Sell = "выключено",
        Hatch = "выключено",
        Collect = "выключено",
        Hop = "выключено",
    }
    return self
end

local function getRoot()
    local player = game:GetService("Players").LocalPlayer
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart"), character
end

local function teleport(position, height)
    local root = getRoot()
    if not root or not position then return false end
    root.CFrame = CFrame.new(position + Vector3.new(0, height or 2.5, 0))
    return true
end

local function firePrompt(prompt)
    if not prompt then return false end
    if fireproximityprompt then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then return true end
    end
    if getconnections then
        local ok, connections = pcall(getconnections, prompt.Triggered)
        if ok and type(connections) == "table" then
            for _, connection in ipairs(connections) do
                pcall(function() connection:Fire() end)
            end
            return true
        end
    end
    return false
end

local function invoke(remote, ...)
    if not remote then return nil, "missing" end
    local args = {...}
    if remote:IsA("RemoteFunction") then
        local ok, result = pcall(function() return remote:InvokeServer(unpack(args)) end)
        if ok then return true, result end
        return nil, tostring(result)
    end
    local ok = pcall(function() remote:FireServer(unpack(args)) end)
    if ok then return true end
    return nil, "fire failed"
end

-- Try several argument shapes; the game accepts {Uid = ...} per research.
local function invokeSell(remote, uid)
    local shapes = {
        function() return invoke(remote, {Uid = uid}) end,
        function() return invoke(remote, uid) end,
        function() return invoke(remote) end,
    }
    for _, shape in ipairs(shapes) do
        local ok = shape()
        if ok then return true end
    end
    return false
end

function Automation:IsRarityAllowed(id, list)
    if type(list) ~= "table" or #list == 0 then return true end
    for _, entry in ipairs(list) do
        if tostring(entry) == tostring(id) then return true end
    end
    return false
end

function Automation:IsBelowKeep(rank)
    local keep = self.Config.Settings.KeepRarities or {}
    local keepRanks = {}
    for _, id in ipairs(keep) do
        keepRanks[self.Rarity.Rank(id)] = true
    end
    -- Sell everything that is NOT in the keep list (by id, not rank compare)
    return keepRanks[rank] == nil
end

function Automation:PickTarget()
    local records = self.Eggs:Scan()
    local settings = self.Config.Settings
    local candidates = self.Eggs:Filter(records, {
        Rarities = settings.RarityFilter,
        MaxDistance = settings.StealRadius,
    })
    -- Skip eggs sitting in our own base area
    local home = self.Positions:GetHome()
    local ownBaseRadius = 55
    local best = nil
    for _, record in ipairs(candidates) do
        local inBase = home and record.Position and (record.Position - home).Magnitude < ownBaseRadius
        if not inBase and record.Position then
            if not best then
                best = record
            elseif settings.StealPriority == "distance" then
                if record.Distance < best.Distance then best = record end
            elseif record.Rank > best.Rank or (record.Rank == best.Rank and record.Distance < best.Distance) then
                best = record
            end
        end
    end
    return best
end

function Automation:StealOne(record)
    local settings = self.Config.Settings
    record = record or self:PickTarget()
    if not record or not record.Position then return false, "целей нет" end

    if settings.StealTeleport then
        teleport(record.Position)
        task.wait(0.15)
    end

    local networking = self.Network:GetFolder()
    local askCarry = networking and networking:FindFirstChild("RF/EggWorld/AskFieldEggCarry")
    local ok = invoke(askCarry, {Uid = record.Uid})
    local promptOk = firePrompt(record.Prompt)

    -- Give the server a moment, then walk home and place.
    task.wait(0.3)
    local placed = false
    if settings.AutoReturn then
        local home = self.Positions:GetHome()
        if home then
            if settings.StealTeleport then
                teleport(home, 3)
                task.wait(0.3)
            end
            local uid = self.Eggs:GetHeldEggUid()
            if uid then
                local askPlace = networking and networking:FindFirstChild("RF/EggWorld/AskPlaceEgg")
                placed = invoke(askPlace, {LocalCFrame = CFrame.new(0, 0, 0), Uid = uid})
            end
        end
    end
    return ok or promptOk or placed, string.format("%s [%s]", record.Name, record.Rarity)
end

function Automation:DropHeld()
    local player = game:GetService("Players").LocalPlayer
    local pgui = player:FindFirstChild("PlayerGui")
    local dropGui = pgui and pgui:FindFirstChild("DropHeldEgg")
    local dropButton = dropGui and dropGui:FindFirstChild("Button", true)
    if dropButton then
        if firesignal then
            pcall(firesignal, dropButton.MouseButton1Click)
            pcall(firesignal, dropButton.Activated)
        end
        if getconnections then
            pcall(function()
                for _, connection in ipairs(getconnections(dropButton.MouseButton1Click)) do connection:Fire() end
                for _, connection in ipairs(getconnections(dropButton.Activated)) do connection:Fire() end
            end)
        end
        return true
    end

    local networking = self.Network:GetFolder()
    for _, name in ipairs({"RF/EggWorld/AskFieldEggDrop", "RE/EggWorld/AskFieldEggDrop"}) do
        local remote = networking and networking:FindFirstChild(name)
        if remote then
            local uid = self.Eggs:GetHeldEggUid()
            invoke(remote, {Uid = uid})
            return true
        end
    end
    return false
end

function Automation:PlaceHeldEggs()
    local networking = self.Network:GetFolder()
    local askPlace = networking and networking:FindFirstChild("RF/EggWorld/AskPlaceEgg")
    if not askPlace then return 0 end

    local player = game:GetService("Players").LocalPlayer
    local containers = {player.Character, player:FindFirstChild("Backpack")}
    local count = 0
    for _, container in ipairs(containers) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and item:GetAttribute("UID")
                    and (item:GetAttribute("ItemType") == "AssetEgg" or string.find(string.lower(item.Name), "egg", 1, true)) then
                    local ok = invoke(askPlace, {LocalCFrame = CFrame.new(0, 0, 0), Uid = item:GetAttribute("UID")})
                    if ok then count = count + 1 end
                end
            end
        end
    end
    return count
end

function Automation:HatchReady()
    local player = game:GetService("Players").LocalPlayer
    local pgui = player:FindFirstChild("PlayerGui")
    local growing = pgui and pgui:FindFirstChild("GrowingEggs")
    local fired = 0

    if growing then
        for _, button in ipairs(growing:GetDescendants()) do
            if button:IsA("GuiButton") and button.Visible then
                if firesignal then
                    pcall(firesignal, button.MouseButton1Click)
                    pcall(firesignal, button.Activated)
                    fired = fired + 1
                end
                if getconnections then
                    pcall(function()
                        for _, connection in ipairs(getconnections(button.MouseButton1Click)) do connection:Fire(); fired = fired + 1 end
                        for _, connection in ipairs(getconnections(button.Activated)) do connection:Fire(); fired = fired + 1 end
                    end)
                end
            end
            if fired > 6 then break end
        end
    end

    -- Remote fallback for eggs placed near home
    local networking = self.Network:GetFolder()
    local askHatch = networking and networking:FindFirstChild("RF/EggWorld/AskHatch")
    if askHatch then
        local home = self.Positions:GetHome()
        if home then
            for _, record in ipairs(self.Eggs:Scan()) do
                if record.Position and (record.Position - home).Magnitude < 60 and fired < 8 then
                    local ok = invoke(askHatch, {Uid = record.Uid})
                    if ok then fired = fired + 1 end
                end
            end
        end
    end
    return fired
end

function Automation:CollectEarnings()
    local networking = self.Network:GetFolder()
    local collect = networking and networking:FindFirstChild("RF/AwayEarnings/AskCollect")
    if not collect then return false end
    local ok = invoke(collect, {Kind = "Claim"})
    return ok == true
end

function Automation:WearTreadmill()
    local networking = self.Network:GetFolder()
    local wear = networking and networking:FindFirstChild("RF/Treadmill/AskWearStill")
    if wear then invoke(wear) end

    local workspace = game:GetService("Workspace")
    local treadmill = workspace:FindFirstChild("Treadmills") or workspace:FindFirstChild("Gym")
    if treadmill then
        local prompt = treadmill:FindFirstChildWhichIsA("ProximityPrompt", true)
        firePrompt(prompt)
    end
    return true
end

function Automation:SellOnce()
    local settings = self.Config.Settings
    local remotes = self.Eggs:FindSellRemotes()
    local soldEggs, soldPets = 0, 0
    local remoteByKind = {Egg = nil, Pet = nil}
    for _, remote in ipairs(remotes) do
        local lowered = string.lower(remote.Name)
        if not remoteByKind.Egg and string.find(lowered, "egg", 1, true) then remoteByKind.Egg = remote end
        if not remoteByKind.Pet and (string.find(lowered, "pet", 1, true) or string.find(lowered, "roster", 1, true)) then remoteByKind.Pet = remote end
    end

    if settings.AutoSellEggs then
        local home = self.Positions:GetHome()
        for _, record in ipairs(self.Eggs:Scan()) do
            if record.Position and home and (record.Position - home).Magnitude < 70
                and self:IsBelowKeep(self.Rarity.Rank(record.Rarity)) then
                local target = remoteByKind.Egg or remotes[1]
                if target and invokeSell(target, record.Uid) then soldEggs = soldEggs + 1 end
            end
        end
    end

    if settings.AutoSellPets then
        local roster = self.Eggs:GetPetRoster()
        if type(roster) == "table" then
            for _, pet in pairs(roster) do
                if type(pet) == "table" then
                    local uid = pet.Uid or pet.UID or pet.Id
                    local rarityId = self.Rarity.FromRecord(pet)
                    if uid and self:IsBelowKeep(self.Rarity.Rank(rarityId)) then
                        local target = remoteByKind.Pet or remoteByKind.Egg or remotes[1]
                        if target and invokeSell(target, uid) then soldPets = soldPets + 1 end
                    end
                end
            end
        end
    end
    return soldEggs, soldPets, #remotes
end

function Automation:ServerHop()
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local player = game:GetService("Players").LocalPlayer
    local requestFn = request or http_request or (syn and syn.request)
    pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        if requestFn then
            local response = requestFn({Url = url, Method = "GET"})
            if response and response.Body then
                local data = HttpService:JSONDecode(response.Body)
                for _, server in ipairs(data.data or {}) do
                    if server.playing < server.maxPlayers and server.id ~= game.JobId then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, player)
                        return
                    end
                end
            end
        end
        TeleportService:Teleport(game.PlaceId, player)
    end)
end

function Automation:FeedMonster()
    local root = getRoot()
    if not root then return false end
    local networking = self.Network:GetFolder()
    local eggsFolder = self.Eggs:GetEggFolders()[1]
    local target = nil
    if eggsFolder then
        for _, model in ipairs(eggsFolder:GetChildren()) do
            if string.find(string.lower(model.Name), "parasite", 1, true) then
                target = model
                break
            end
        end
    end
    if not target then return false end
    local part = target:IsA("BasePart") and target or target:FindFirstChildWhichIsA("BasePart", true)
    if part then
        teleport(part.Position)
        task.wait(0.2)
        local feed = networking and networking:FindFirstChild("RF/MonsterParasite/AskFeed")
        invoke(feed)
        return true
    end
    return false
end

function Automation:Start(alive)
    if self.Running then return end
    self.Running = true
    local settings = self.Config.Settings
    local lastSell = 0
    local lastCollect = 0
    local lastTreadmill = 0
    local lastPlace = 0
    local lastHatch = 0

    task.spawn(function()
        while self.Running and alive() do
            local now = os.clock()
            local ok, err = pcall(function()
                -- Auto steal loop
                if settings.AutoSteal then
                    local held = self.Eggs:GetHeldEgg()
                    if settings.AutoDrop and held then
                        self:DropHeld()
                        self.Status.Steal = "сброшено из рук"
                    elseif not held then
                        local done, info = self:StealOne()
                        self.EmptyRuns = done and 0 or self.EmptyRuns + 1
                        self.Status.Steal = done and ("украдено: " .. tostring(info)) or ("цели нет (" .. tostring(info) .. ")")
                        if settings.AutoServerHop and self.EmptyRuns >= (settings.HopEmptyRuns or 12) and now - self.LastHop > 30 then
                            self.LastHop = now
                            self.Status.Hop = "переключаемся..."
                            self:ServerHop()
                        end
                    else
                        self.Status.Steal = "яйцо в руках"
                    end
                elseif settings.AutoServerHop then
                    self.Status.Hop = "включён (требует автокражу)"
                end

                -- Auto place
                if settings.AutoPlace and now - lastPlace > 1.5 then
                    lastPlace = now
                    local count = self:PlaceHeldEggs()
                    if count > 0 then self.Status.Steal = "размещено: " .. count end
                end

                -- Auto hatch
                if settings.AutoHatch and now - lastHatch > 2 then
                    lastHatch = now
                    local count = self:HatchReady()
                    self.Status.Hatch = count > 0 and ("вылуплено: " .. count) or "жду готовые яйца"
                end

                -- Auto collect
                if settings.AutoCollect and now - lastCollect > 30 then
                    lastCollect = now
                    local ok2 = self:CollectEarnings()
                    self.Status.Collect = ok2 and "доход собран" or "ремоут не найден"
                end

                -- Treadmill
                if settings.AutoTreadmill and now - lastTreadmill > 60 then
                    lastTreadmill = now
                    self:WearTreadmill()
                    self.Status.Treadmill = "на дорожке"
                end

                -- Auto sell
                if (settings.AutoSellEggs or settings.AutoSellPets) and now - lastSell > math.max(3, settings.SellInterval or 10) then
                    lastSell = now
                    local soldEggs, soldPets, remotes = self:SellOnce()
                    if remotes == 0 then
                        self.Status.Sell = "Sell-ремоуты не найдены"
                    else
                        self.Status.Sell = string.format("яиц: %d, питомцев: %d (ремоутов %d)", soldEggs, soldPets, remotes)
                    end
                end
            end)
            if not ok then self.Status.Steal = "ошибка: " .. tostring(err) end
            task.wait(math.max(0.4, settings.StealDelay or 2))
        end
    end)
end

function Automation:Destroy()
    self.Running = false
end

return Automation
