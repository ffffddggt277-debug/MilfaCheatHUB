-- MilfaCheatHUB • Murder Mystery 2
-- Combat: knife aura, kill all, sheriff auto-shot, silent aims,
-- auto-dodge v0.2.0.
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
local UserInputService = game:GetService("UserInputService")

local Combat = {}

Combat.AuraEnabled = false
Combat.SheriffAutoEnabled = false
Combat.DodgeEnabled = false
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
local dodgeRunning = false
local lastAuraAt = 0
local lastShotAt = 0
local lastThrowAt = 0
local lastDodgeAt = 0
local dodgeConnections = {}
local watchedProjectiles = {}  -- [part] = время_до_которого_следим

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

-- Прямая видимость между корнями (обе модели исключены из рейкаста:
-- hit == nil значит между нами чисто, препятствий нет).
local function hasLineOfSight(myRoot, targetRoot, targetCharacter)
    local origin = myRoot.Position
    local direction = targetRoot.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    if localPlayer.Character then exclude[#exclude + 1] = localPlayer.Character end
    if targetCharacter then exclude[#exclude + 1] = targetCharacter end
    params.FilterDescendantsInstances = exclude
    local hit = workspace:Raycast(origin, direction, params)
    return hit == nil
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
        return false, "нужна роль ШЕРИФ/ГЕРОЙ"
    end
    local character, myRoot = getCharacterParts()
    local gun = character and findTool(character, "Gun")
    if not gun then
        Combat.Status = "пистолет не найден"
        return false, "пистолет не найден"
    end
    if not myRoot then
        return false, "нет персонажа"
    end

    local murderers = RolesRef.FindByRole("Murderer")
    if #murderers == 0 then
        return false, "маньяк неизвестен — обнови роли"
    end
    for _, name in ipairs(murderers) do
        local target = Players:FindFirstChild(name)
        local root = target and aliveTargetRoot(target)
        if root and target and target.Character then
            local dist = (root.Position - myRoot.Position).Magnitude
            if dist <= (settings.SheriffRange or 300) then
                -- LOS: стреляем только если между нами нет препятствий.
                if not hasLineOfSight(myRoot, root, target.Character) then
                    Combat.Status = "маньяк за препятствием"
                    return false, "маньяк за препятствием"
                end
                local ok = pcall(function()
                    local beamLocal = gun:FindFirstChild("KnifeLocal")
                    local createBeam = beamLocal and beamLocal:FindFirstChild("CreateBeam")
                    local remote = createBeam and createBeam:FindFirstChildOfClass("RemoteFunction")
                    if remote then
                        remote:InvokeServer(1, root.Position, "AH2")
                    else
                        local shoot = gun:FindFirstChild("Shoot")
                        if shoot then
                            shoot:FireServer(CFrame.new(myRoot.Position), CFrame.new(root.Position))
                        end
                    end
                end)
                if ok then
                    Combat.LastKillName = name
                    Combat.KillCount = Combat.KillCount + 1
                    Combat.Status = "выстрел: " .. name
                    if Combat.OnNotify then pcall(Combat.OnNotify, "Выстрел в маньяка: " .. name) end
                    lastShotAt = os.clock()
                    return true, "выстрел в " .. name
                end
                lastShotAt = os.clock()
                return false, "ремоут выстрела не сработал"
            end
        end
    end
    return false, "маньяк вне дистанции"
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
-- MurderAim: тихий бросок ножа в шерифа (одиночный, кнопка/клавиша).
-- Ремоут: Character.Knife.Events.KnifeThrown:FireServer(fromCF, toCF)
-- (см. FINDINGS_MM2.md, секция C/D).
---------------------------------------------------------------------

function Combat.MurderAimThrow()
    local settings = ConfigRef.Settings
    if not RolesRef.LocalIsMurderer() then
        Combat.Status = "нужна роль МАНЬЯК"
        return false, "нужна роль МАНЬЯК"
    end
    local character, myRoot = getCharacterParts()
    local knife = character and findTool(character, "Knife")
    if not knife then
        Combat.Status = "нож не найден"
        return false, "нож не найден"
    end
    if not myRoot then
        return false, "нет персонажа"
    end
    local sheriffs = RolesRef.FindByRole("Sheriff")
    if #sheriffs == 0 then
        return false, "шериф неизвестен — обнови роли"
    end
    local target = Players:FindFirstChild(sheriffs[1])
    local root = target and aliveTargetRoot(target)
    if not root or not (target and target.Character) then
        return false, "шериф недоступен"
    end
    local dist = (root.Position - myRoot.Position).Magnitude
    if dist > (settings.AimMaxDistance or 260) then
        return false, string.format("далеко: %.0fм", dist)
    end
    if os.clock() - lastThrowAt < 1.0 then
        return false, "нож ещё летит (перезарядка)"
    end
    if not hasLineOfSight(myRoot, root, target.Character) then
        Combat.Status = "шериф за препятствием"
        return false, "шериф за препятствием"
    end

    local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") or myRoot
    local from = hand.CFrame
    local to = CFrame.new(root.Position)
    local ok = pcall(function()
        local events = knife:FindFirstChild("Events")
        local thrown = events and events:FindFirstChild("KnifeThrown")
        if thrown then
            thrown:FireServer(from, to)
        else
            local throw = knife:FindFirstChild("Throw")
            if throw then
                throw:FireServer(from, to)
            else
                error("нет ремоута")
            end
        end
    end)
    lastThrowAt = os.clock()
    if not ok then
        Combat.Status = "ремоут броска не найден"
        return false, "ремоут броска не найден"
    end
    Combat.LastKillName = sheriffs[1]
    Combat.Status = "бросок ножа: " .. sheriffs[1]
    if Combat.OnNotify then pcall(Combat.OnNotify, "Бросок ножа в шерифа: " .. sheriffs[1]) end
    return true, "бросок в " .. sheriffs[1]
end

---------------------------------------------------------------------
-- SheriffAim: тот же тихий выстрел, но по кнопке/клавише (без цикла).
---------------------------------------------------------------------

function Combat.SheriffAimShot()
    return trySheriffShot()
end

---------------------------------------------------------------------
-- Бросок ножа в точку прицела (троллинг/утилита маньяка).
---------------------------------------------------------------------

function Combat.ThrowAtAim()
    if not RolesRef.LocalIsMurderer() then
        return false, "нужна роль МАНЬЯК"
    end
    local character, myRoot = getCharacterParts()
    local knife = character and findTool(character, "Knife")
    if not knife then return false, "нож не найден" end
    if not myRoot then return false, "нет персонажа" end
    if os.clock() - lastThrowAt < 1.0 then
        return false, "нож ещё летит (перезарядка)"
    end
    local camera = workspace.CurrentCamera
    if not camera then return false, "нет камеры" end
    local targetPoint = nil
    pcall(function()
        local mouse = UserInputService:GetMouseLocation()
        local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        if localPlayer.Character then params.FilterDescendantsInstances = { localPlayer.Character } end
        local result = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
        targetPoint = result and result.Position or (ray.Origin + ray.Direction * 200)
    end)
    if not targetPoint then
        targetPoint = (camera.CFrame * CFrame.new(0, 0, -150)).Position
    end
    local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") or myRoot
    local ok = pcall(function()
        local events = knife:FindFirstChild("Events")
        local thrown = events and events:FindFirstChild("KnifeThrown")
        if thrown then
            thrown:FireServer(hand.CFrame, CFrame.new(targetPoint))
        else
            local throw = knife:FindFirstChild("Throw")
            if throw then throw:FireServer(hand.CFrame, CFrame.new(targetPoint)) end
        end
    end)
    lastThrowAt = os.clock()
    if not ok then return false, "ремоут броска не найден" end
    Combat.Status = "бросок в прицел"
    return true, "бросок выполнен"
end

---------------------------------------------------------------------
-- AutoDodge: резкий стрейф от летящих ножей и стрелков в упор.
-- Снаряды ловим событием DescendantAdded (дёшево для телефона) и
-- следим за ними 4 секунды; стрейф — перпендикулярно траектории.
---------------------------------------------------------------------

local DODGE_NAMES = { "knife", "throw", "projectile", "bullet" }

local function isDodgeName(name)
    local lowered = string.lower(name)
    for _, fragment in ipairs(DODGE_NAMES) do
        if string.find(lowered, fragment, 1, true) then return true end
    end
    return false
end

local function trackProjectile(part)
    if watchedProjectiles[part] then return end
    watchedProjectiles[part] = os.clock() + 4
end

local function dodgeNow(myRoot, threatPosition)
    local settings = ConfigRef.Settings
    local power = settings.DodgePower or 12
    local base = threatPosition - myRoot.Position
    base = Vector3.new(base.X, 0, base.Z)
    if base.Magnitude < 0.5 then base = myRoot.CFrame.LookVector end
    base = base.Unit
    local perp = Vector3.new(-base.Z, 0, base.X)
    if math.random() < 0.5 then perp = -perp end
    local target = myRoot.Position + perp * power - base * (power * 0.2) + Vector3.new(0, 2, 0)
    myRoot.CFrame = CFrame.lookAt(target, target - base)
    lastDodgeAt = os.clock()
    Combat.Status = "dodge!"
end

local function dodgeLoop()
    while dodgeRunning do
        local _, myRoot = getCharacterParts()
        if myRoot then
            local now = os.clock()
            if now - lastDodgeAt > (ConfigRef.Settings.DodgeCooldown or 1.2) then
                local dodged = false
                -- 1) летящие в нас снаряды (ножи)
                for part, deadline in pairs(watchedProjectiles) do
                    if dodged then break end
                    if now > deadline or not part.Parent then
                        watchedProjectiles[part] = nil
                    else
                        local ok, threat = pcall(function()
                            local velocity = part.AssemblyLinearVelocity
                            local speed = velocity.Magnitude
                            if speed < 20 then return false end
                            local offset = myRoot.Position - part.Position
                            local dist = offset.Magnitude
                            if dist > (ConfigRef.Settings.DodgeRadius or 45) or dist < 2 then return false end
                            return velocity.Unit:Dot(offset.Unit) > 0.82
                        end)
                        if ok and threat then
                            dodgeNow(myRoot, part.Position)
                            dodged = true
                        end
                    end
                end
                -- 2) стрелок/маньяк в упор смотрит на нас (пуля хитскан —
                -- уклоняемся ЗАРАНЕЕ, пока целятся)
                if not dodged then
                    for _, player in ipairs(Players:GetPlayers()) do
                        if dodged then break end
                        if player ~= localPlayer and RolesRef.IsAlive(player.Name) then
                            local role = RolesRef.Get(player.Name)
                            local character = player.Character
                            local root = character and character:FindFirstChild("HumanoidRootPart")
                            if root and (role == "Murderer" or role == "Sheriff" or role == "Hero") then
                                local dist = (root.Position - myRoot.Position).Magnitude
                                if dist < 16 then
                                    local look = root.CFrame.LookVector
                                    local toMe = (myRoot.Position - root.Position).Unit
                                    if look:Dot(toMe) > 0.78 then
                                        dodgeNow(myRoot, root.Position)
                                        dodged = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.12)
    end
end

function Combat.SetDodge(value)
    Combat.DodgeEnabled = value and true or false
    ConfigRef.Settings.AutoDodge = Combat.DodgeEnabled
    if value and not dodgeRunning then
        dodgeRunning = true
        -- подписка на новые снаряды
        dodgeConnections[#dodgeConnections + 1] = workspace.DescendantAdded:Connect(function(descendant)
            if dodgeRunning and descendant:IsA("BasePart") and isDodgeName(descendant.Name) then
                trackProjectile(descendant)
            end
        end)
        -- существующие снаряды на момент включения
        pcall(function()
            for _, descendant in ipairs(workspace:GetDescendants()) do
                if descendant:IsA("BasePart") and isDodgeName(descendant.Name) then
                    trackProjectile(descendant)
                end
            end
        end)
        task.spawn(dodgeLoop)
    elseif not value then
        dodgeRunning = false
        for _, connection in ipairs(dodgeConnections) do
            pcall(function() connection:Disconnect() end)
        end
        dodgeConnections = {}
        watchedProjectiles = {}
        Combat.Status = "выключено"
    end
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
    dodgeRunning = false
    for _, connection in ipairs(dodgeConnections) do
        pcall(function() connection:Disconnect() end)
    end
    dodgeConnections = {}
    watchedProjectiles = {}
end

return Combat
