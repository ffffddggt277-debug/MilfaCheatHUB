-- MilfaCheatHUB • Murder Mystery 2
-- Combat: knife aura, kill all, sheriff auto-shot v0.1.0.
--
-- All of this uses the game's OWN knife/gun remotes — the same replication
-- path a legitimate stab takes (verified across working hubs):
--   * stab:  Character.Knife.Events.KnifeStabbed:FireServer()
--            Character.Knife.Events.HandleTouched:FireServer(targetRoot)
--   * touch fallback: firetouchinterest(Handle, targetRoot, 0/1)
--   * sheriff shot: Gun.KnifeLocal.CreateBeam.RemoteFunction:InvokeServer(
--            1, targetPosition, "AH2") — the SERVER does the hit test.
-- Requirements: murderer needs the Knife in Character (server enforces);
-- sheriff needs the Gun. These are the highest-report features — every call
-- is humanized and rate-capped, and the UI marks them as risky.

local Players = game:GetService("Players")

local Combat = {}

Combat.AuraEnabled = false
Combat.SheriffAutoEnabled = false
Combat.LastKillName = "—"
Combat.KillCount = 0
Combat.Status = "выключено"
Combat.Debug = false
Combat.OnNotify = nil

local ConfigRef = nil
local RolesRef = nil
local StealthRef = nil

local localPlayer = Players.LocalPlayer
local auraRunning = false
local sheriffRunning = false
local lastAuraAt = 0
local lastShotAt = 0

local function note(...)
    if Combat.Debug then print("[mh combat]", ...) end
end

local function jitter(value)
    if ConfigRef and ConfigRef.Settings.HumanizeDelays then
        return value * (0.8 + math.random() * 0.5)
    end
    return value
end

local function getCharacterParts()
    local character = localPlayer.Character
    if not character then return nil, nil end
    return character, character:FindFirstChild("HumanoidRootPart")
end

local function findTool(character, name)
    if character and character:FindFirstChild(name) then
        return character:FindFirstChild(name)
    end
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    if backpack and backpack:FindFirstChild(name) then
        pcall(function() character.Humanoid:EquipTool(backpack:FindFirstChild(name)) end)
        return character and character:FindFirstChild(name)
    end
    return nil
end

local function aliveTargetRoot(targetPlayer)
    local character = targetPlayer.Character
    if not character then return nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health > 0 and root then
        return root
    end
    return nil
end

local function nearbyTargets(radius, maxCount)
    local _, myRoot = getCharacterParts()
    if not myRoot then return {} end
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and RolesRef.IsAlive(player.Name) then
            local root = aliveTargetRoot(player)
            if root and (root.Position - myRoot.Position).Magnitude <= radius then
                list[#list + 1] = { Player = player, Root = root }
                if maxCount and #list >= maxCount then break end
            end
        end
    end
    return list
end

---------------------------------------------------------------------
-- Knife stab replication (murderer only)
---------------------------------------------------------------------

local function stabTarget(knife, targetRoot)
    local ok = pcall(function()
        local events = knife:FindFirstChild("Events")
        if events then
            local stabbed = events:FindFirstChild("KnifeStabbed")
            local touched = events:FindFirstChild("HandleTouched")
            if stabbed then stabbed:FireServer() end
            if touched and targetRoot then touched:FireServer(targetRoot) end
            return
        end
        -- Older builds: Knife.Stab with Down/Up.
        local stab = knife:FindFirstChild("Stab")
        if stab then
            stab:FireServer(targetRoot and targetRoot.Position or "Down")
        end
    end)
    -- Physical touch fallback: replicate the handle touching the victim.
    if ok == nil or ok then
        pcall(function()
            local handle = knife:FindFirstChild("Handle") or knife:FindFirstChildWhichIsA("BasePart")
            if handle and type(firetouchinterest) == "function" then
                firetouchinterest(handle, targetRoot, 0)
                firetouchinterest(handle, targetRoot, 1)
            end
        end)
    end
end

---------------------------------------------------------------------
-- Aura loop
---------------------------------------------------------------------

local function auraLoop()
    while auraRunning do
        local settings = ConfigRef.Settings
        if not RolesRef.LocalIsMurderer() then
            Combat.Status = "нужна роль МАНЬЯК"
        else
            local character, _ = getCharacterParts()
            local knife = character and findTool(character, "Knife")
            if not knife then
                Combat.Status = "нож не найден"
            else
                local targets = nearbyTargets(settings.AuraRadius or 14, 3)
                if #targets == 0 then
                    Combat.Status = "целей рядом нет"
                else
                    for _, target in ipairs(targets) do
                        stabTarget(knife, target.Root)
                        Combat.KillCount = Combat.KillCount + 1
                        Combat.LastKillName = target.Player.Name
                        Combat.Status = "аура: " .. target.Player.Name
                        task.wait(jitter(math.max(0.5, settings.AuraDelay or 1.0)))
                    end
                end
            end
        end
        task.wait(jitter(0.4))
    end
end

---------------------------------------------------------------------
-- Sheriff auto-shot
---------------------------------------------------------------------

local function trySheriffShot()
    local settings = ConfigRef.Settings
    if not RolesRef.LocalIsSheriff() then
        Combat.Status = "нужна роль ШЕРИФ/ГЕРОЙ"
        return
    end
    local character, _ = getCharacterParts()
    local gun = character and findTool(character, "Gun")
    if not gun then
        Combat.Status = "пистолет не найден"
        return
    end

    local murderers = RolesRef.FindByRole("Murderer")
    for _, name in ipairs(murderers) do
        local target = Players:FindFirstChild(name)
        local root = target and aliveTargetRoot(target)
        if root then
            local _, myRoot = getCharacterParts()
            if myRoot and (root.Position - myRoot.Position).Magnitude <= (settings.SheriffRange or 300) then
                -- LOS check so we do not shoot through walls blindly.
                local camera = workspace.CurrentCamera
                local origin = myRoot.Position
                local direction = root.Position - origin
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = { localPlayer.Character }
                local hit = workspace:Raycast(origin, direction, params)
                local visible = hit and hit.Instance and hit.Instance:IsDescendantOf(target.Character)
                if visible then
                    local ok = pcall(function()
                        local beamLocal = gun:FindFirstChild("KnifeLocal")
                        local createBeam = beamLocal and beamLocal:FindFirstChild("CreateBeam")
                        local remote = createBeam and createBeam:FindFirstChildOfClass("RemoteFunction")
                        if remote then
                            remote:InvokeServer(1, root.Position, "AH2")
                        else
                            local shoot = gun:FindFirstChild("Shoot")
                            if shoot then
                                shoot:FireServer(CFrame.new(origin), CFrame.new(root.Position))
                            end
                        end
                    end)
                    if ok then
                        Combat.LastKillName = name
                        Combat.KillCount = Combat.KillCount + 1
                        Combat.Status = "выстрел: " .. name
                        if Combat.OnNotify then pcall(Combat.OnNotify, "Выстрел в маньяка: " .. name) end
                    end
                    lastShotAt = os.clock()
                    return
                end
            end
        end
    end
end

local function sheriffLoop()
    while sheriffRunning do
        local ok, err = pcall(trySheriffShot)
        if not ok then note("sheriff: " .. tostring(err)) end
        task.wait(jitter(1.2))
    end
end

---------------------------------------------------------------------
-- Kill all (manual button, murderer only)
---------------------------------------------------------------------

function Combat.KillAll()
    if not RolesRef.LocalIsMurderer() then
        return false, "нужна роль МАНЬЯК"
    end
    local character, _ = getCharacterParts()
    local knife = character and findTool(character, "Knife")
    if not knife then
        return false, "нож не найден"
    end
    local targets = nearbyTargets(60, 12)
    if #targets == 0 then
        return false, "никого в радиусе 60"
    end
    task.spawn(function()
        for _, target in ipairs(targets) do
            local fresh = getCharacterParts()
            local freshKnife = fresh and findTool(fresh, "Knife")
            if freshKnife then
                stabTarget(freshKnife, target.Root)
                Combat.KillCount = Combat.KillCount + 1
                Combat.LastKillName = target.Player.Name
            end
            task.wait(jitter(0.45))
        end
        Combat.Status = "kill all: " .. tostring(#targets) .. " целей"
    end)
    return true, "целей: " .. tostring(#targets)
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

function Combat.SetAura(value)
    Combat.AuraEnabled = value and true or false
    ConfigRef.Settings.KnifeAura = Combat.AuraEnabled
    if value and not auraRunning then
        auraRunning = true
        task.spawn(auraLoop)
    elseif not value then
        auraRunning = false
        Combat.Status = "выключено"
    end
end

function Combat.SetSheriffAuto(value)
    Combat.SheriffAutoEnabled = value and true or false
    ConfigRef.Settings.SheriffAuto = Combat.SheriffAutoEnabled
    if value and not sheriffRunning then
        sheriffRunning = true
        task.spawn(sheriffLoop)
    elseif not value then
        sheriffRunning = false
        Combat.Status = "выключено"
    end
end

function Combat.Configure(config, roles, stealth)
    ConfigRef = config
    RolesRef = roles
    StealthRef = stealth
    Combat.Debug = config.Settings.DebugLogs == true
end

function Combat.Destroy()
    auraRunning = false
    sheriffRunning = false
end

return Combat
