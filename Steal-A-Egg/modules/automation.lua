-- MilfaCheatHUB • automation engine v0.4 (stealth)
-- Auto steal / place / hatch / sell / collect / treadmill / upgrades / pets / traps / server hop.
-- Remote shapes are RSpy-confirmed (see LIST.md). All teleports glide, all delays humanized.

local Automation = {}
Automation.__index = Automation
local AutomationRef = nil
AutomationRef = Automation

function Automation.new(config, eggs, network, positions, scanner, rarity, stealth)
    local self = setmetatable({}, Automation)
    self.Config = config
    self.Eggs = eggs
    self.Network = network
    self.Positions = positions
    self.Scanner = scanner
    self.Rarity = rarity
    self.Stealth = stealth
    self.Running = false
    self.EmptyRuns = 0
    self.LastHop = 0
    self.TreadmillName = nil
    self.Status = {
        Steal = "выключено",
        Sell = "выключено",
        Hatch = "выключено",
        Collect = "выключено",
        Hop = "выключено",
        Treadmill = "выключено",
        Upgrades = "выключено",
        Pets = "выключено",
        Traps = "выключено",
    }
    return self
end

local function getRoot()
    local player = game:GetService("Players").LocalPlayer
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart"), character
end

-- BAC-safe teleport: glide like fast walking instead of a 300-stud CFrame jump.
-- Yields while gliding so remote calls fire only when we actually arrived.
local function teleport(position, height, glideSpeed)
    local root = getRoot()
    if not root or not position then return false end
    local stealth = AutomationRef and AutomationRef.Stealth
    if stealth and stealth.GlideTo and AutomationRef.Config.Settings.SafeTeleport then
        stealth.SafeTeleport = true
        stealth.GlideSpeed = glideSpeed or AutomationRef.Config.Settings.GlideSpeed or 48
        pcall(stealth.GlideTo, stealth, position, {Height = height or 2.5})
        return true
    end
    root.CFrame = CFrame.new(position + Vector3.new(0, height or 2.5, 0))
    return true
end

local function pause(base)
    local stealth = AutomationRef and AutomationRef.Stealth
    local value = base
    if AutomationRef and AutomationRef.Config.Settings.HumanizeDelays then
        if stealth and stealth.Jitter then
            value = stealth.Jitter(base)
        else
            value = base * (0.75 + math.random() * 0.6)
        end
    end
    if value and value > 0 then task.wait(value) end
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
        pause(0.2)
    end

    local networking = self.Network:GetFolder()
    local askCarry = networking and networking:FindFirstChild("RF/EggWorld/AskFieldEggCarry")
    -- RSpy: single table with BOTH Uid and FirstAreaSlotKey (mandatory for first areas)
    local carryArgs = {Uid = record.Uid}
    local slotKey = self.Eggs:ParseFirstAreaSlotKey(record.Uid, record)
    if slotKey then carryArgs.FirstAreaSlotKey = slotKey end
    local ok = invoke(askCarry, carryArgs)
    local promptOk = firePrompt(record.Prompt)

    -- Give the server a moment, then walk home and place.
    pause(0.35)
    local placed = false
    if settings.AutoReturn then
        local home = self.Positions:GetHome()
        if home then
            if settings.StealTeleport then
                teleport(home, 3)
                pause(0.3)
            end
            local uid = self.Eggs:GetHeldEggUid()
            if uid then
                local askPlace = networking and networking:FindFirstChild("RF/EggWorld/AskPlaceEgg")
                placed = invoke(askPlace, {Uid = tostring(uid), LocalCFrame = CFrame.new(0, -0.5, 0)})
            end
        end
    end
    local where = slotKey and (" (" .. tostring(slotKey) .. ")") or ""
    return ok or promptOk or placed, string.format("%s [%s]%s", record.Name, record.Rarity, where)
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
                    local ok = invoke(askPlace, {Uid = tostring(item:GetAttribute("UID")), LocalCFrame = CFrame.new(0, -0.5, 0)})
                    if ok then count = count + 1 end
                    pause(0.2)
                end
            end
        end
    end
    return count
end

function Automation:HatchReady()
    local player = game:GetService("Players").LocalPlayer
    local networking = self.Network:GetFolder()
    local askHatch = networking and networking:FindFirstChild("RF/EggWorld/AskHatch")
    local fired = 0
    local cap = math.max(1, self.Config.Settings.MaxHatchPerTick or 4)

    -- 1) Best source: placed eggs from save.EggInventory. RSpy: AskHatch("hex-uid") — plain string.
    local inv = self.Eggs:GetEggInventory()
    if askHatch and inv then
        for uid, entry in pairs(inv) do
            if fired >= cap then break end
            if type(entry) == "table" and entry.Placement ~= nil and not entry.Locked then
                local ok = invoke(askHatch, tostring(uid))
                if ok then fired = fired + 1; pause(0.2) end
            end
        end
    end

    -- 2) GUI fallback: GrowingEggs ready buttons
    local pgui = player:FindFirstChild("PlayerGui")
    local growing = pgui and pgui:FindFirstChild("GrowingEggs")
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
            if fired > cap then break end
        end
    end

    -- 3) Remote fallback for eggs placed near home (plain string uid)
    if askHatch and fired < cap then
        local home = self.Positions:GetHome()
        if home then
            for _, record in ipairs(self.Eggs:Scan()) do
                if record.Position and (record.Position - home).Magnitude < 60 and fired < cap then
                    local ok = invoke(askHatch, tostring(record.Uid))
                    if ok then fired = fired + 1; pause(0.2) end
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
    -- RSpy: AskCollect({Kind = "Claim"})
    local ok = invoke(collect, {Kind = "Claim"})
    return ok == true
end

function Automation:WearTreadmill()
    local networking = self.Network:GetFolder()
    local wear = networking and networking:FindFirstChild("RF/Treadmill/AskWearStill")
    -- RSpy: AskWearStill() — no arguments
    if wear then invoke(wear) end

    local workspace = game:GetService("Workspace")
    local treadmill = workspace:FindFirstChild("Treadmills") or workspace:FindFirstChild("Gym")
    if treadmill then
        local prompt = treadmill:FindFirstChildWhichIsA("ProximityPrompt", true)
        firePrompt(prompt)
    end
    return true
end

function Automation:DoffTreadmill()
    local networking = self.Network:GetFolder()
    local doff = networking and networking:FindFirstChild("RF/Treadmill/AskDoff")
    if not doff then return false end
    local ok = invoke(doff)
    return ok == true
end

function Automation:FindTreadmillName()
    if self.TreadmillName then return self.TreadmillName end
    local workspace = game:GetService("Workspace")
    local roots = {
        workspace:FindFirstChild("Treadmills"),
        workspace:FindFirstChild("Gym"),
    }
    local objects = workspace:FindFirstChild("__OBJECTS")
    if objects then roots[#roots + 1] = objects end
    for _, root in ipairs(roots) do
        if root then
            for _, descendant in ipairs(root:GetDescendants()) do
                if descendant:IsA("Model") or descendant:IsA("BasePart") then
                    if string.find(descendant.Name, "Treadmill", 1, true)
                        or string.find(string.lower(descendant.Name), "treadmill", 1, true) then
                        self.TreadmillName = descendant.Name
                        return self.TreadmillName
                    end
                end
            end
        end
    end
    -- RSpy-captured default
    self.TreadmillName = "FlameTreadmill"
    return self.TreadmillName
end

function Automation:UpgradeTreadmill()
    local networking = self.Network:GetFolder()
    local raise = networking and networking:FindFirstChild("RF/Treadmill/AskTierRaise")
    if not raise then return false end
    -- RSpy: AskTierRaise("FlameTreadmill") — treadmill id string
    local ok = invoke(raise, self:FindTreadmillName())
    return ok == true
end

function Automation:UpgradeBase()
    local networking = self.Network:GetFolder()
    local raise = networking and networking:FindFirstChild("RE/Homestead/AskBaseTierRaise")
    if not raise then return false end
    -- RSpy: RE/Homestead/AskBaseTierRaise:FireServer() — no arguments
    local ok = pcall(function() raise:FireServer() end)
    return ok
end

function Automation:WearBestPets()
    local settings = self.Config.Settings
    local networking = self.Network:GetFolder()
    local inv = self.Eggs:GetPetInventory()
    if type(inv) ~= "table" then return false, "инвентарь не читается" end

    local wear = networking and networking:FindFirstChild("RF/PenRoster/AskWear")
    if not wear then return false, "PenRoster/AskWear не найден" end

    -- Rank every unlocked pet, wear the best ones into free slots
    local list = {}
    for uid, entry in pairs(inv) do
        if type(entry) == "table" and not entry.Locked and not entry.InFuse then
            local rarity = self.Rarity.Detect(tostring(entry.Rarity or ""))
                or self.Rarity.FromCategory(tostring(entry.AssetCategory or ""))
                or self.Rarity.FromRecord(entry)
            list[#list + 1] = {Uid = tostring(uid), Rank = self.Rarity.Rank(rarity)}
        end
    end
    table.sort(list, function(left, right) return left.Rank > right.Rank end)

    local trigger = networking and networking:FindFirstChild("RE/ToolTrigger/Trigger")
    local best = networking and networking:FindFirstChild("RF/Haul/FetchWearBestStatus")
    local slots = math.max(1, settings.PetSlots or 3)
    local worn = 0
    for index, item in ipairs(list) do
        if worn >= slots then break end
        -- RSpy flow: ToolTrigger/Trigger(Tool) then PenRoster/AskWear(uid), then FetchWearBestStatus
        if trigger then pcall(function() trigger:FireServer(Instance.new("Tool")) end) end
        local ok = invoke(wear, item.Uid)
        if ok then worn = worn + 1 end
        pause(0.25)
    end
    if best then pcall(function() best:InvokeServer() end) end
    return worn > 0, "надето: " .. worn
end

function Automation:NeutralizeTraps()
    local player = game:GetService("Players").LocalPlayer
    local debris = workspace:FindFirstChild("__DEBRIS")
    if not debris then return 0 end
    local me = tostring(player.UserId)
    local count = 0
    for _, trap in ipairs(debris:GetChildren()) do
        if trap.Name == "PlayerTrap" then
            local owner = trap:GetAttribute("Owner") or trap:GetAttribute("OwnerUserId")
            if owner ~= nil and tostring(owner) ~= me and tostring(owner) ~= player.Name then
                pcall(function()
                    if trap:IsA("BasePart") then
                        trap.CanTouch = false
                        trap.CanQuery = false
                    end
                    for _, part in ipairs(trap:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanTouch = false
                            part.CanQuery = false
                        end
                    end
                end)
                count = count + 1
            end
        end
    end
    return count
end

function Automation:SellOnce()
    local settings = self.Config.Settings
    local remotes = self.Eggs:FindSellRemotes()
    local soldEggs, soldPets = 0, 0
    local sell = remotes[1]
    if not sell then return 0, 0, 0 end

    local networking = self.Network:GetFolder()
    local wearTool = networking and networking:FindFirstChild("RF/EggWorld/AskWearTool")
    local perTick = math.max(1, settings.SellPerTick or 8)
    local sellPause = math.max(0.05, settings.SellPerDelay or 0.15)

    local function sellRemoteCall(...)
        if sell:IsA("RemoteEvent") then
            local ok = pcall(function(...) sell:FireServer(...) end, ...)
            if ok then return true end
            return false
        end
        return invoke(sell, ...) == true
    end

    -- 1) Eggs via save.EggInventory: wear tool, then SellPet({uid}) — RSpy-confirmed shapes
    if settings.AutoSellEggs then
        local inv = self.Eggs:GetEggInventory()
        if inv then
            for uid, entry in pairs(inv) do
                if soldEggs >= perTick then break end
                if type(entry) == "table" and not entry.Placement and not entry.Locked then
                    local rarity = self.Rarity.FromCategory(tostring(entry.AssetCategory or ""))
                        or self.Rarity.FromRecord(entry)
                    if not self:IsRarityAllowed(rarity, settings.KeepRarities) then
                        local ok = false
                        if wearTool then
                            invoke(wearTool, tostring(uid))
                            pause(0.12)
                        end
                        ok = sellRemoteCall({tostring(uid)}) or sellRemoteCall(tostring(uid))
                        if ok then soldEggs = soldEggs + 1 end
                        pause(sellPause)
                    end
                end
            end
        else
            -- Fallback: eggs placed near home (scan-based)
            local home = self.Positions:GetHome()
            for _, record in ipairs(self.Eggs:Scan()) do
                if soldEggs >= perTick then break end
                if record.Position and home and (record.Position - home).Magnitude < 70
                    and self:IsBelowKeep(self.Rarity.Rank(record.Rarity)) then
                    local ok = false
                    if wearTool then
                        invoke(wearTool, tostring(record.Uid))
                        pause(0.12)
                    end
                    ok = sellRemoteCall({tostring(record.Uid)}) or sellRemoteCall(tostring(record.Uid))
                    if ok then soldEggs = soldEggs + 1 end
                    pause(sellPause)
                end
            end
        end
    end

    -- 2) Pets via save.Inventory: SellPet(uid) — RSpy-confirmed shape
    if settings.AutoSellPets then
        local inv = self.Eggs:GetPetInventory()
        if inv then
            for uid, entry in pairs(inv) do
                if soldPets >= perTick then break end
                if type(entry) == "table" and not entry.Locked and not entry.IsFavorite and not entry.InFuse then
                    local rarity = self.Rarity.Detect(tostring(entry.Rarity or ""))
                        or self.Rarity.FromCategory(tostring(entry.AssetCategory or ""))
                        or self.Rarity.FromRecord(entry)
                    if not self:IsRarityAllowed(rarity, settings.KeepRarities) then
                        local ok = sellRemoteCall(tostring(uid)) or sellRemoteCall({tostring(uid)})
                        if ok then soldPets = soldPets + 1 end
                        pause(sellPause)
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
        pause(0.3)
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
    local lastDoff = 0
    local lastTreadmillUpgrade = 0
    local lastBaseUpgrade = 0
    local lastPets = 0
    local lastTraps = 0

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
                if settings.AutoHatch and now - lastHatch > 3 then
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

                -- Treadmill wear + optional doff cycle
                if settings.AutoTreadmill and now - lastTreadmill > math.max(20, settings.TreadmillInterval or 60) then
                    lastTreadmill = now
                    self:WearTreadmill()
                    self.Status.Treadmill = "на дорожке"
                end
                if settings.AutoDoff and now - lastDoff > 5 then
                    lastDoff = now
                    if self:DoffTreadmill() then
                        self.Status.Treadmill = "сошли, ждём повторный AskWearStill"
                    end
                end

                -- Upgrades (treadmill + base)
                if (settings.AutoTreadmillUpgrade or settings.AutoBaseUpgrade) and now - lastTreadmillUpgrade > math.max(30, settings.UpgradeInterval or 90) then
                    lastTreadmillUpgrade = now
                    if settings.AutoTreadmillUpgrade then
                        local okTm = self:UpgradeTreadmill()
                        self.Status.Upgrades = okTm and "дорожка улучшена" or "дорожка: отклонено/максимум"
                    end
                    if settings.AutoBaseUpgrade then
                        local okBase = self:UpgradeBase()
                        self.Status.Upgrades = (self.Status.Upgrades or "upgrade") .. " • база: " .. (okBase and "улучшена" or "отклонено/максимум")
                    end
                end

                -- Best pets auto-wear
                if settings.AutoPetsBest and now - lastPets > 120 then
                    lastPets = now
                    local okPets, info = self:WearBestPets()
                    self.Status.Pets = okPets and ("лучшие питомцы (" .. tostring(info) .. ")") or ("питомцы: " .. tostring(info))
                end

                -- Trap neutralizer
                if settings.NeutralizeTraps and now - lastTraps > 3 then
                    lastTraps = now
                    local count = self:NeutralizeTraps()
                    self.Status.Traps = count > 0 and ("отключено ловушек: " .. count) or "ловушек нет"
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
            -- Humanized loop delay: never a fixed robotic interval (BAC rate heuristics).
            local loopDelay = math.max(1.0, settings.StealDelay or 2)
            if settings.HumanizeDelays then loopDelay = loopDelay * (0.85 + math.random() * 0.4) end
            task.wait(loopDelay)
        end
    end)
end

function Automation:Destroy()
    self.Running = false
end

return Automation
